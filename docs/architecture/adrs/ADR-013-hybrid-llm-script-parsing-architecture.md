# ADR-013: Hybrid Architecture for LLM-based Script Parsing

**Status**: Proposed  
**Date**: 2026-06-17  
**Author**: Architecture Decision

---

## Context

Breakdown RS requires automated processing of PDF scripts to extract structured data (scenes, locations, costumes, timing) for costume scheduling in film productions. This feature involves:

- **PDF Upload**: Users upload script PDFs via the web interface
- **Async Processing**: Background batch processing to extract context model
- **Structured Output**: Convert unstructured PDFs into `SceneContext` objects with scenes, costumes, special features

### Critical Constraints

1. **Data Protection & NDA Compliance**: 
   - Scripts are extremely sensitive (NDAs, IP protection)
   - EU AI Act 2026 compliance required (minimal risk systems)
   - No script data may leave the infrastructure without explicit guarantees

2. **Cost Neutrality**:
   - Fixed operating costs preferred over variable API costs
   - Development phase involves hundreds of test imports (prompt tuning)

3. **Vendor Independence**:
   - Avoid lock-in to OpenAI, Anthropic, or specific local setups
   - Ability to switch LLM providers without code changes

### Economic Analysis: Token Costs vs. Fixed Infrastructure

A typical script (100-120 pages, ~40,000 words) requires approximately **100,000 tokens** (input + output including prompting, chunking overhead, and structured JSON responses).

| Approach / Provider | Model Type | Cost per Script | Break-Even vs. Netcup Flatrate (~€20/month) |
|---------------------|-------------|-----------------|----------------------------------------------|
| **Hybrid (OpenRouter)** | Small OS model (e.g., *Llama 3.1 8B*) | ~$0.003 | ~6,500 scripts/month |
| **Hybrid (OpenRouter)** | Large OS model (e.g., *Qwen 2.5 72B*) | ~$0.04 | ~500 scripts/month |
| **Frontier (Direct)** | Whole PDF to *Gemini Pro / GPT-4o* | ~$0.25 – $0.50 | ~40 to 80 scripts/month |
| **EuroRouter.ai** | EU-hosted OS models | Prices + ~€39 base | Only economical at very high volume |
| **Self-Hosted (Netcup)** | Local OS model (e.g., *Qwen 2.5 7B*) | **€0.00** | From second 1 (fixed costs) |

**Key Insight**: During development, hundreds of test imports for prompt tuning make cloud frontier models economically unviable.

### Netcup Infrastructure Evaluation (AMD EPYC 9645 with AVX-512)

| Server Model | Specs (DDR5 RAM / NVMe) | Price / Month | Target Model (CPU Inference via Ollama) |
|--------------|--------------------------|---------------|------------------------------------------|
| **RS 1000 G12 Pro** | 4 dedicated cores, 8 GB RAM | ~€12.00 | Llama 3.2 (3B) / Phi-3 (3.8B) |
| **RS 2000 G12 Pro** | 8 dedicated cores, 16 GB RAM | ~€19.85 | **Preferred**: Qwen 2.5 (7B) / Llama 3.1 (8B) quantized |

---

## Decision Drivers

1. **Fixed Cost Guarantee**: Predictable €20/month vs. variable API costs scaling with usage
2. **IP Protection for Customers**: Script data must never leave our infrastructure (or must have zero-data-retention guarantees)
3. **Evolutionary Architecture**: Ability to switch from development (cloud) to production (self-hosted) without code changes
4. **EU AI Act Compliance**: Minimal risk classification, no prohibited practices
5. **Scalability**: Async background processing must handle multiple script uploads concurrently

---

## Considered Options

### Option 1: Purely Deterministic Parser (Regex/Rule-based)

Extract script data using traditional NLP techniques without LLMs.

- **Pros**:
  - No LLM costs
  - Full data sovereignty (runs locally)
  - Deterministic results
  
- **Cons**:
  - **Rejected**: Layout inflexibility (scripts have wildly different formats)
  - Cannot extract semantic information (costume descriptions, scene summaries)
  - Maintenance nightmare for different script formats (US vs. EU formats)
  
- **Why not**: Insufficient for production use; cannot handle real-world script variability

### Option 2: Cloud Frontier Models with Native PDF Input

Send entire PDFs to GPT-4o or Gemini Pro with native PDF understanding.

- **Pros**:
  - Highest accuracy (frontier models)
  - No local infrastructure setup
  - Simple implementation (single API call)
  
- **Cons**:
  - **Rejected**: Variable costs scale with usage (~$0.25-0.50 per script)
  - **NDA risks**: Scripts sent to US-based cloud providers
  - Vendor lock-in to OpenAI/Google
  - EU AI Act compliance unclear for third-country transfers
  
- **Why not**: Unacceptable data protection risks and unpredictable costs

### Option 3: Hybrid Approach with Trait Abstraction and Local Inference Target ✅

Fuzzy chunking in Rust + LLM-based semantic extraction with pluggable infrastructure.

- **Pros**:
  - **Economic**: Fixed costs (~€20/month) after break-even
  - **Data sovereignty**: Self-hosted option keeps scripts on-premise
  - **Flexible**: Trait abstraction allows switching providers
  - **Evolutionary**: Start with OpenRouter (dev), migrate to self-hosted (prod)
  
- **Cons**:
  - DevOps effort for Docker-Ollama setup
  - CPU inference latency (acceptable for async background batch)
  
- **Why chosen**: Best balance of cost, security, and flexibility

---

## Decision

We will implement a **hybrid LLM architecture** with Rust trait abstraction, fuzzy chunking, and evolutionary infrastructure (OpenRouter → Self-hosted Ollama).

### Architecture Overview

```
PDF Upload → [PDF Text Extraction] → [Fuzzy Chunking] → [LLM Scene Analysis] → [SceneContext] → Event Store
                     ↓                                           ↓
              pdftotext -layout                         Trait: ScriptParser
                                                     (Ollama / OpenRouter)
```

### 1. Fuzzy Chunking (Rust)

The PDF is ingested via a simple, robust text extractor (`pdftotext -layout`). A regex approach splits the text roughly based on scene headings (`INT.` / `EXT.`). Uncertainties in splitting are handled by the LLM's semantic intelligence.

```rust
// Example: Fuzzy scene splitting
pub fn extract_scenes(raw_text: &str) -> Vec<SceneChunk> {
    let scene_heading_regex = Regex::new(r"^\s*(INT\.|EXT\.|I/E\.)\s+.*$").unwrap();
    // Split and handle edge cases...
}
```

**Why fuzzy?** Perfect chunking is unnecessary; the LLM understands context across boundaries.

### 2. Abstraction Layer (Trait)

The AI interaction is encapsulated behind a Rust trait to make the inference engine transparently exchangeable via configuration.

```rust
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SceneContext {
    pub scene_number: String,
    pub location: String,
    pub time_of_day: String,
    pub summary: String,
    pub costumes: Vec<String>,
    pub special_features: Vec<String>,
}

#[async_trait]
pub trait ScriptParser: Send + Sync {
    async fn analyze_scene(&self, scene_text: &str) -> Result<SceneContext, String>;
}

// Implementation for local Ollama
pub struct OllamaScriptParser {
    pub client: reqwest::Client,
    pub endpoint: String,
    pub model_name: String,
}

#[async_trait]
impl ScriptParser for OllamaScriptParser {
    async fn analyze_scene(&self, scene_text: &str) -> Result<SceneContext, String> {
        // HTTP POST to local Ollama instance with structured outputs
        let response = self.client
            .post(format!("{}/api/generate", self.endpoint))
            .json(&serde_json::json!({
                "model": self.model_name,
                "prompt": format!("Extract scene context as JSON:\n{}", scene_text),
                "format": "json",
                "stream": false
            }))
            .send()
            .await
            .map_err(|e| e.to_string())?;
        
        // Parse and return SceneContext
        unimplemented!("Parse response")
    }
}

// Implementation for OpenRouter (development)
pub struct OpenRouterScriptParser {
    pub api_key: String,
    pub model_name: String,
    pub client: reqwest::Client,
}

#[async_trait]
impl ScriptParser for OpenRouterScriptParser {
    async fn analyze_scene(&self, scene_text: &str) -> Result<SceneContext, String> {
        // HTTP POST to eu.openrouter.ai (Zero-Data-Retention)
        unimplemented!("OpenRouter implementation")
    }
}
```

### 3. Infrastructure Evolution

#### Development Phase
- **Provider**: OpenRouter (EU endpoint `eu.openrouter.ai` with Zero-Data-Retention)
- **Model**: Smaller open-source models (Llama 3.1 8B, Qwen 2.5 7B)
- **Why**: Cost-effective for hundreds of test imports during prompt tuning

#### Production Phase
- **Provider**: Self-hosted on Netcup Root Server (RS 2000 G12 Pro recommended)
- **Model**: Qwen 2.5 (7B) or Llama 3.1 (8B) quantized via Ollama in Docker
- **Why**: Fixed costs, full data sovereignty, EU AI Act compliant

```yaml
# docker-compose.yml for production
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        limits:
          cpus: '8'
          memory: 16G
```

### 4. Async Processing Integration

The script parsing integrates with the existing CQRS/Event Sourcing architecture:

```rust
// Command: UploadScript
#[derive(Command)]
pub struct UploadScript {
    pub script_id: Uuid,
    pub file_path: String,
}

// Event: ScriptUploaded
#[derive(Event)]
pub struct ScriptUploaded {
    pub script_id: Uuid,
    pub uploaded_at: DateTime<Utc>,
}

// Async Batch Processor (kameo actor)
pub struct ScriptProcessingActor {
    pub parser: Box<dyn ScriptParser>,
}

impl Actor for ScriptProcessingActor {
    async fn on_command(&mut self, cmd: ProcessScript) -> Result<(), Error> {
        let scenes = self.parser.analyze_scene(&cmd.scene_text).await?;
        // Emit events: SceneExtracted, CostumesIdentified, etc.
        Ok(())
    }
}
```

---

## Consequences

### Positive

- ✅ **Predictable fixed costs**: ~€20/month regardless of script volume (after break-even)
- ✅ **Data sovereignty**: Scripts never leave our infrastructure in production (self-hosted)
- ✅ **Decoupling via chunking**: Scene-level chunking minimizes context window overflow risks
- ✅ **Evolutionary**: Start cheap (OpenRouter), migrate to production (self-hosted) without code changes
- ✅ **EU AI Act compliant**: Minimal risk system, no prohibited practices, data stays in EU
- ✅ **No vendor lock-in**: `ScriptParser` trait allows switching between Ollama, OpenRouter, or future providers
- ✅ **Async processing**: Background batch processing doesn't block user interactions

### Negative / Risks

- ⚠️ **DevOps overhead**: Docker-Ollama setup requires initial configuration and maintenance
- ⚠️ **CPU inference latency**: Slower than GPU inference (acceptable for async background batch)
- ⚠️ **Model quality dependency**: Open-source models may be less accurate than frontier models for edge cases
- ⚠️ **Prompt engineering effort**: Significant effort required to tune prompts for consistent structured output

### Risk Mitigation

- **DevOps**: Provide Terraform/Ansible scripts for Netcup server setup
- **Latency**: Use quantized models (Q4_K_M) for faster CPU inference; acceptable for background processing
- **Model quality**: Start with larger OS models (72B) via OpenRouter; migrate to smaller self-hosted models after validation
- **Prompt engineering**: Implement automated testing with golden datasets; use structured outputs (JSON mode) to ensure parseable results

---

## Implementation Plan

### Phase 1: Development (OpenRouter)
1. Implement `ScriptParser` trait
2. Implement `OpenRouterScriptParser` with EU endpoint
3. Build fuzzy chunking logic (PDF → text → scenes)
4. Create async processing actor (kameo)
5. Add prompt engineering test suite

### Phase 2: Production Preparation (Self-Hosted)
1. Set up Netcup RS 2000 G12 Pro server
2. Deploy Ollama via Docker Compose
3. Implement `OllamaScriptParser`
4. Load-test with representative scripts
5. Tune quantization level (accuracy vs. speed)

### Phase 3: Migration & Operations
1. Feature flag to switch between OpenRouter and Ollama
2. Gradual rollout to production
3. Monitor inference times and accuracy metrics
4. Set up logging (tracing) for debugging

---

## Dependencies (Cargo.toml)

```toml
[dependencies]
async-trait = "0.1"
serde = { version = "1.0", features = ["derive"] }
reqwest = { version = "0.12", features = ["json"] }
regex = "1.1"
pdf-extract = "0.7"  # or use pdftotext CLI wrapper
kameo = "0.11"
```

---

## Testing Strategy

### Unit Tests
- Test fuzzy chunking with different script formats
- Mock `ScriptParser` trait for handler tests

### Integration Tests
- Test `OllamaScriptParser` against local Ollama instance
- Test `OpenRouterScriptParser` with test API key

### Property-Based Tests
- Generate random scene texts; verify `SceneContext` parsing
- Test edge cases (empty scenes, malformed text)

### Load Tests
- Simulate multiple concurrent script uploads
- Measure inference time per scene on target hardware

---

## Notes

- **EU AI Act**: Self-hosted open-source models qualify as "minimal risk" systems
- **Zero-Data-Retention**: OpenRouter EU endpoint guarantees no data storage
- **Model Updates**: Plan for model versioning and fallback strategies
- **Cost Monitoring**: Track actual token usage vs. estimates; adjust chunking strategy if needed

### Related Decisions

- **PDF Extraction**: Evaluate `pdf-extract` crate vs. `pdftotext` CLI
- **Structured Outputs**: Use JSON mode / grammar constraints for reliable parsing
- **Error Handling**: Integrate with `AppError` (see ADR-012) for parse failures

### Resources

- [Ollama Documentation](https://ollama.ai/docs)
- [OpenRouter EU Endpoint](https://eu.openrouter.ai/docs)
- [EU AI Act Compliance Guidelines](https://artificialintelligenceact.eu/)
- [Rust Async Trait Patterns](https://smallcultfollowing.com/babysteps/blog/2023/03/01/async-fn-in-trait-part-9/)

---

**Related ADRs**:
- [ADR-001: Hexagonal Architecture](./ADR-001-hexagonal-architecture.md)
- [ADR-005: Use Axum as Web Framework](./ADR-005-use-axum.md)
- [ADR-012: Error Handling with thiserror and anyhow](./ADR-012-error-handling-thiserror-anyhow.md)

**Next Steps**:
- Implement `ScriptParser` trait in `crates/core`
- Create `OpenRouterScriptParser` in `crates/infra` (dev feature flag)
- Set up local Ollama for testing
- Design prompt engineering test suite
