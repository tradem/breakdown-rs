// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/**
 * graph-first nudge — a SOFT advisory for text search on code symbols.
 *
 * ## Why this exists
 *
 * The repo convention is graph-first code discovery (`AGENTS.md` §2,
 * `.github/instructions/flutter-code-discovery.instructions.md`): the
 * `codebase-memory` knowledge graph answers *meaning* questions (who defines X,
 * who calls X, what breaks if I change X), text search answers *occurrence*
 * questions (is this exact string there). Prose alone did not hold: an agent
 * under time pressure reaches for `rg`, because `rg` is one call away and its
 * answer looks complete — while it structurally cannot see the difference
 * between a definition, a call, an import, a doc-comment mention and a string
 * literal, and cannot report edge types or completeness at all.
 *
 * This extension does not block anything (an earlier design that blocked `rg`
 * was rejected: an advisory that shows the better answer in place is both
 * kinder and harder to ignore). When a text search targets a symbol-shaped
 * token in code, it appends the code-aware result to the SAME tool result:
 * definitions with kind + file:line, and inbound call edges where the graph
 * models them. The agent sees the comparison for free, at the moment of the
 * decision, instead of reading a rule it has already skipped.
 *
 * Deliberately NOT nudged (text search is the CORRECT tool there, and a nudge
 * that fires there would destroy its own credibility):
 *   - ARB catalogs / Markdown / YAML / JSON / lock files / PlantUML
 *   - anything under `docs/`, `openspec/`, `vendor/`, `node_modules/`
 *   - test trees (a search inside tests is usually a fixture hunt)
 *   - phrase or regex patterns (they are not symbol lookups)
 *
 * Escape hatches: `PI_GRAPH_NUDGE=0` disables it for a session, a
 * `# literal:` marker in the command disables it for that one call.
 *
 * Honest limits, surfaced in the appended block rather than hidden:
 *   - Dart class CONSTRUCTION sites are not modelled as call edges (a class
 *     reports 0 inbound even when four screens push it) — the block says so and
 *     points at `analyze_ast_impact` instead of pretending the graph answered.
 *   - Riverpod `ref.watch` wiring is invisible at tree-sitter level; for "who
 *     observes this provider" `rg` genuinely wins. `scripts/who-watches.sh`
 *     combines both for that question.
 *   - An empty result is reported as *possibly stale index* (with the freshness
 *     command), never as "no such symbol".
 *
 * Cost control: one `search_graph` (and at most one `trace_path`) per nudged
 * call, 4 s timeout each, a 12 s cooldown, a 40-nudge session cap, and every
 * failure is silent. No network, read-only CLI calls, no index mutation.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Binary name (same seam as `scripts/reindex-graph.sh`). */
const DEFAULT_BIN = "codebase-memory-mcp";

/** Text-search binaries this advisory covers. */
const SEARCH_COMMANDS = new Set([
	"rg",
	"grep",
	"egrep",
	"fgrep",
	"ag",
	"ack",
]);

/** Text-file / non-code targets where `rg` is the RIGHT tool. */
const TEXT_TARGET_RE =
	/\.(arb|md|markdown|ya?ml|json|lock|txt|feature|puml|po|pot|csv|conf|env)$/i;

/** Directories that carry no symbol-level code (or are pruned from the index). */
const NON_CODE_DIR_RE =
	/(^|\/)(docs|openspec|vendor|node_modules|build|\.dart_tool|\.pi|\.github|\.codebase-memory)\//;

/** Localization catalogs and generated l10n trees: key lookups are text lookups. */
const L10N_DIR_RE = /(^|\/)(l10n|i18n|locale|locales)(\/|$)/;

/** Test trees: a text search here is usually a fixture hunt, not an impact question. */
const TEST_DIR_RE = /(^|\/)(test|tests|integration_test)\//;

const COOLDOWN_MS = 12_000;
const SESSION_CAP = 40;
const CLI_TIMEOUT_MS = 4_000;
const MAX_HITS = 3;
const MAX_CALLERS = 3;

/** Symbol shapes that make a text search a *meaning* question. */
const PASCAL_RE = /^[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+$/;
const CAMEL_RE = /^[a-z][a-z0-9]*(?:[A-Z][a-z0-9]*)+$/;
const SNAKE_RE = /^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/;
const CONST_RE = /^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$/;

/** Flags whose VALUE is not the search pattern. */
const VALUE_FLAGS = new Set([
	"-e",
	"--regexp",
	"-g",
	"--glob",
	"-t",
	"--type",
	"-T",
	"--type-not",
	"-m",
	"--max-count",
	"-A",
	"-B",
	"-C",
	"--context",
	"--iglob",
	"-f",
	"--file",
]);

export type NudgeDecision = {
	/** The symbol-shaped token the search is about. */
	symbol: string;
	/** True for PascalCase — construction sites are not graph edges. */
	classLike: boolean;
};

const isSymbol = (token: string): boolean =>
	token.length >= 6 &&
	(PASCAL_RE.test(token) ||
		CAMEL_RE.test(token) ||
		SNAKE_RE.test(token) ||
		CONST_RE.test(token));

/**
 * Splits a shell command line into simple command segments.
 *
 * Deliberately naive (no shell parser): the goal is to recognise a plain
 * `rg <pattern> <paths>` invocation, not to execute anything. Anything it
 * misparses simply yields "no nudge", which is the safe direction.
 */
export function splitCommands(command: string): string[][] {
	return command
		.split(/\|\||&&|[|;\n]/)
		.map((segment) => segment.trim())
		.filter((segment) => segment.length > 0)
		.map((segment) => segment.split(/\s+/));
}

/**
 * Decides whether a shell command is a text search that should be nudged.
 *
 * Returns `null` for everything that is not a symbol-shaped search over code —
 * including every case where `rg` is the correct tool.
 */
export function decide(command: string): NudgeDecision | null {
	if (command.includes("# literal:")) return null;

	for (const words of splitCommands(command)) {
		// Skip leading env assignments (`FOO=1 rg …`).
		let i = 0;
		while (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i]!)) i++;
		const bin = words[i]?.replace(/^.*\//, "");
		if (!bin || !SEARCH_COMMANDS.has(bin)) continue;

		let pattern: string | null = null;
		const paths: string[] = [];
		for (let j = i + 1; j < words.length; j++) {
			const word = words[j]!;
			if (word === "--") continue;
			if (word.startsWith("-")) {
				if (VALUE_FLAGS.has(word)) {
					// The flag's VALUE still tells us what is being searched (a
					// `-g '*.arb'` glob is a text target), so it joins the path hints.
					const value = words[j + 1];
					if (value !== undefined) paths.push(value);
					j++;
				}
				continue;
			}
			if (pattern === null) {
				pattern = word;
				continue;
			}
			paths.push(word);
		}
		if (pattern === null) continue;

		// A quoted phrase, a regex or a path-ish glob is not a symbol lookup.
		const bare = pattern.replace(/^['"]|['"]$/g, "");
		if (!isSymbol(bare)) continue;

		// The search targets text files / non-code trees → rg is the right tool.
		const unquote = (p: string) => p.replace(/^['"]|['"]$/g, "");
		if (paths.some((p) => TEXT_TARGET_RE.test(unquote(p)))) continue;
		if (
			paths.some((p) => {
				const clean = unquote(p);
				return (
					NON_CODE_DIR_RE.test(clean) ||
					TEST_DIR_RE.test(clean) ||
					L10N_DIR_RE.test(clean)
				);
			})
		) {
			continue;
		}
		return { symbol: bare, classLike: PASCAL_RE.test(bare) };
	}
	return null;
}

/** Rows → objects using the envelope's own `cols` (no schema guessing). */
function rowsToObjects(payload: unknown): Record<string, unknown>[] {
	if (!payload || typeof payload !== "object") return [];
	const { cols, rows } = payload as { cols?: unknown; rows?: unknown };
	if (!Array.isArray(cols) || !Array.isArray(rows)) return [];
	return (rows as unknown[][]).map((row) => {
		const obj: Record<string, unknown> = {};
		(cols as string[]).forEach((col, idx) => {
			obj[col] = row[idx];
		});
		return obj;
	});
}

/** Code files only: generated outputs and text trees are noise, not answers. */
function isCodeFile(file: string): boolean {
	return (
		/\.(dart|rs|ts|tsx|js|jsx|mjs|cjs|py|sql|kt|kts|swift|go|java|rb|php|cs|cc|cpp|c|h|hpp)$/i.test(
			file,
		) && !/\.(g|freezed|mocks|chopper)\.dart$/i.test(file)
	);
}

/** Definition labels, used only to break ties between equally-ranked rows. */
const LABEL_ORDER = [
	"Class",
	"Struct",
	"Enum",
	"Interface",
	"Trait",
	"Function",
	"Method",
	"Constant",
	"Type",
	"Property",
	"Union",
];

/**
 * Code hits for [symbol], in the engine's own relevance order.
 *
 * Two filters, both learned the hard way: (1) generated outputs and doc trees
 * are dropped (an unfiltered lookup for a provider returned 8 of 8 `.g.dart`
 * hits, which is what makes the graph *look* useless); (2) the last qualified
 * name segment must BE the symbol — a pure BM25 match otherwise returns an
 * unrelated class that merely shares vocabulary, and a wrong hit is worse than
 * no hit for an advisory.
 */
export function pickHits(
	payload: unknown,
	symbol?: string,
): Record<string, unknown>[] {
	const rows = rowsToObjects(payload).filter((row) => {
		if (typeof row.file !== "string" || !isCodeFile(row.file as string)) {
			return false;
		}
		if (!symbol) return true;
		const qn = String(row.qn ?? "");
		return qn === symbol || qn.endsWith(`.${symbol}`);
	});
	// Stable: the engine already ordered by relevance. Only equal-relevance rows
	// (e.g. a class and its methods at the same rank) are ordered by kind so the
	// definition is read first.
	return rows
		.map((row, index) => ({ row, index }))
		.sort((a, b) => {
			const rankA = typeof a.row.rank === "number" ? (a.row.rank as number) : 0;
			const rankB = typeof b.row.rank === "number" ? (b.row.rank as number) : 0;
			if (rankA !== rankB) return rankA - rankB;
			const labelA = LABEL_ORDER.indexOf(String(a.row.label ?? ""));
			const labelB = LABEL_ORDER.indexOf(String(b.row.label ?? ""));
			const orderA = labelA === -1 ? LABEL_ORDER.length : labelA;
			const orderB = labelB === -1 ? LABEL_ORDER.length : labelB;
			if (orderA !== orderB) return orderA - orderB;
			return a.index - b.index;
		})
		.map(({ row }) => row);
}

type Caller = { owner: string; name: string };

export function pickCallers(payload: unknown): { total: number; callers: Caller[] } {
	if (!payload || typeof payload !== "object") return { total: 0, callers: [] };
	const envelope = payload as {
		callers_total?: unknown;
		callers?: { groups?: unknown };
	};
	const total =
		typeof envelope.callers_total === "number" ? envelope.callers_total : 0;
	const groups = envelope.callers?.groups;
	if (!Array.isArray(groups)) return { total, callers: [] };
	const callers: Caller[] = [];
	for (const group of groups as {
		qn_prefix?: unknown;
		rows?: unknown;
	}[]) {
		const prefix = typeof group.qn_prefix === "string" ? group.qn_prefix : "";
		const owner = prefix.split(".").slice(-1)[0] ?? prefix;
		// `XProvider.create` is the generated getter, not a consumer of X.
		if (/Provider$/.test(owner)) continue;
		if (!Array.isArray(group.rows)) continue;
		for (const row of group.rows as unknown[][]) {
			const name = typeof row?.[0] === "string" ? (row[0] as string) : "";
			if (name) callers.push({ owner, name });
			if (callers.length >= MAX_CALLERS) break;
		}
		if (callers.length >= MAX_CALLERS) break;
	}
	return { total, callers };
}

/** The appended advisory block. Compact by design: it rides on every nudged call. */
export function formatBlock(args: {
	project: string;
	symbol: string;
	hits: { qn: string; label: string; file: string; lines: string }[];
	classLike: boolean;
	callers?: { total: number; callers: Caller[] };
	/** Set when the searched token only exists as a generated alias. */
	matchedAs?: string;
	/** The full "what text search cannot see" framing: first nudge of a session only. */
	verbose?: boolean;
}): string {
	const { project, symbol, hits, classLike, callers, matchedAs, verbose } =
		args;
	const out: string[] = [];
	out.push("");
	out.push(
		`── code-aware (codebase-memory · ${project}) ─────────────────────────`,
	);
	if (verbose) {
		out.push(
			`Text search answered "does this string occur?". For "what does the code do"`,
		);
		out.push(
			`(definition, callers, blast radius) the graph answers with structure — it`,
		);
		out.push(
			`sees kinds and edges, and does not count comments or string literals.`,
		);
	}

	if (hits.length === 0) {
		out.push("");
		out.push(
			`• no code symbol named "${symbol}" in the index — this is NOT proof it is`,
		);
		out.push(
			`  absent: check freshness first (\`scripts/check-graph-freshness.sh\`, then`,
		);
		out.push(`  \`scripts/reindex-graph.sh --if-stale\`).`);
		if (symbol.endsWith("Provider")) {
			out.push(
				`  Riverpod: the provider VARIABLE is generated — search the family name`,
			);
			out.push(
				`  (\`${symbol.replace(/Provider$/, "")}\`); \`ref.watch\` wiring is not a graph edge,`,
			);
			out.push(`  use \`scripts/who-watches.sh\` for "who observes this".`);
		}
		return out.join("\n");
	}

	out.push("");
	if (matchedAs) {
		out.push(
			`(the searched token is generated; matched the hand-written \`${matchedAs}\`)`,
		);
	}
	const shown = matchedAs ?? symbol;
	for (const hit of hits.slice(0, MAX_HITS)) {
		out.push(
			`• ${shown} · ${hit.label} · ${hit.file}:${hit.lines.split("-")[0]}`,
		);
	}
	if (hits.length > MAX_HITS) {
		out.push(`  (+${hits.length - MAX_HITS} more code hits: search_graph)`);
	}
	if (callers && callers.total > 0 && callers.callers.length > 0) {
		const list = callers.callers
			.map((c) => (c.owner ? `${c.owner}.${c.name}` : c.name))
			.join(", ");
		out.push(
			`  inbound: ${callers.total}${list ? ` → ${list}` : ""}${
				callers.total > MAX_CALLERS ? " …" : ""
			}`,
		);
	}
	if (classLike) {
		out.push(
			`  construction sites are NOT graph edges (Dart classes report 0 inbound):`,
		);
		out.push(`  use \`analyze_ast_impact\` (ast-bro) for "who instantiates this".`);
	}
	return out.join("\n");
}

/** Run one read-only codebase-memory tool through its CLI. Never throws. */
async function graphCli(
	exec: (
		command: string,
		args: string[],
		options?: { cwd?: string; signal?: AbortSignal; timeout?: number },
	) => Promise<{ stdout: string; code: number }>,
	tool: string,
	args: Record<string, unknown>,
	opts: { cwd: string; signal?: AbortSignal; bin: string },
): Promise<unknown | null> {
	try {
		const result = await exec(
			opts.bin,
			["cli", "--quiet", tool, JSON.stringify(args)],
			{ cwd: opts.cwd, signal: opts.signal, timeout: CLI_TIMEOUT_MS },
		);
		if (result.code !== 0) return null;
		return JSON.parse(result.stdout);
	} catch {
		return null;
	}
}

export default function graphFirstNudge(pi: ExtensionAPI): void {
	if (process.env.PI_GRAPH_NUDGE === "0") return;

	const bin = process.env.CODEBASE_MEMORY_BIN || DEFAULT_BIN;
	let lastNudgeAt = 0;
	let nudges = 0;
	let projectCache: { value: string | null; at: number } | null = null;

	const resolveProject = async (
		cwd: string,
		signal?: AbortSignal,
	): Promise<string | null> => {
		if (projectCache && Date.now() - projectCache.at < 60_000) {
			return projectCache.value;
		}
		const payload = (await graphCli(
			pi.exec.bind(pi),
			"list_projects",
			{ format: "json" },
			{ cwd, signal, bin },
		)) as { projects?: { name?: string; root_path?: string }[] } | null;
		const projects = payload?.projects ?? [];
		// The index root must CONTAIN the cwd (the index root is the monorepo
		// root, while sessions commonly start in `frontend-flutter/`).
		const match = projects
			.filter(
				(p) => typeof p.root_path === "string" && cwd.startsWith(p.root_path),
			)
			.sort((a, b) => (b.root_path?.length ?? 0) - (a.root_path?.length ?? 0))[0];
		const value = match?.name ?? null;
		projectCache = { value, at: Date.now() };
		return value;
	};

	pi.on("tool_result", async (event, ctx) => {
		try {
			if (event.toolName !== "bash") return;
			const input = event.input as { command?: string } | undefined;
			const command = input?.command;
			if (!command) return;

			const decision = decide(command);
			if (!decision) return;

			// Cooldown + session cap: the nudge must stay cheap and welcome.
			const now = Date.now();
			if (now - lastNudgeAt < COOLDOWN_MS) return;
			if (nudges >= SESSION_CAP) return;

			const cwd = ctx.cwd;
			const project = await resolveProject(cwd, ctx.signal);
			if (!project) return;

			const search = await graphCli(
				pi.exec.bind(pi),
				"search_graph",
				{ project, query: decision.symbol, limit: 30, format: "json" },
				{ cwd, signal: ctx.signal, bin },
			);
			const collect = (payload: unknown, symbol: string) =>
				pickHits(payload, symbol).map((row) => ({
					qn: String(row.qn ?? ""),
					label: String(row.label ?? ""),
					file: String(row.file ?? ""),
					lines: String(row.lines ?? ""),
				}));
			let hits = collect(search, decision.symbol);

			// Riverpod shape: `<family>Provider` exists only in the generated file, so
			// the filtered hit list is empty even though the hand-written family is
			// right there. Retry once on the de-suffixed name instead of reporting
			// "not found" (which would look like a graph failure and teach the wrong
			// lesson — exactly the 8/8 generated-file noise that discredits the tool).
			let matchedAs: string | undefined;
			if (hits.length === 0 && decision.symbol.endsWith("Provider")) {
				const family = decision.symbol.replace(/Provider$/, "");
				// Class-based providers (`@Riverpod class X`) are declared in
				// PascalCase while the generated getter is camelCase — try both.
				const pascal = family.charAt(0).toUpperCase() + family.slice(1);
				for (const candidate of [family, pascal]) {
					if (candidate.length < 6 || !isSymbol(candidate)) continue;
					const retry = await graphCli(
						pi.exec.bind(pi),
						"search_graph",
						{ project, query: candidate, limit: 30, format: "json" },
						{ cwd, signal: ctx.signal, bin },
					);
					const retryHits = collect(retry, candidate);
					if (retryHits.length > 0) {
						hits = retryHits;
						matchedAs = candidate;
						break;
					}
				}
			}

			// Inbound edges only for function-like symbols: a class legitimately
			// reports 0 (construction is not modelled), and printing "0 callers"
			// there would teach the wrong lesson.
			let callers: { total: number; callers: Caller[] } | undefined;
			if (!decision.classLike && hits.length > 0) {
				const trace = await graphCli(
					pi.exec.bind(pi),
					"trace_path",
					{
						project,
						function_name: matchedAs ?? decision.symbol,
						direction: "inbound",
						limit: 25,
						format: "json",
					},
					{ cwd, signal: ctx.signal, bin },
				);
				callers = pickCallers(trace);
			}

			lastNudgeAt = Date.now();
			nudges++;

			const block = formatBlock({
				project,
				symbol: decision.symbol,
				hits,
				classLike: decision.classLike,
				callers,
				matchedAs,
				verbose: nudges === 0,
			});

			const existing = Array.isArray(event.content) ? event.content : [];
			return {
				content: [...existing, { type: "text" as const, text: block }],
			};
		} catch {
			// An advisory must never break a tool result.
			return;
		}
	});
}

// ---------------------------------------------------------------------------
// Self-test: `node .pi/extensions/graph-first-nudge.ts` (Node ≥ 22 strips the
// types; the pi import above is type-only, so nothing resolves at runtime).
// ---------------------------------------------------------------------------
const invokedDirectly =
	typeof process !== "undefined" &&
	Array.isArray(process.argv) &&
	typeof import.meta?.url === "string" &&
	process.argv[1] !== undefined &&
	decodeURIComponent(new URL(import.meta.url).pathname) === process.argv[1];

if (invokedDirectly) {
	const cases: [string, string | null][] = [
		['rg -n "currentMembershipProvider" lib', "currentMembershipProvider"],
		['rg -n "AiConfigScreen" lib test', "AiConfigScreen"],
		['rg -n "transport\\." lib', null],
		['rg -n "settingsAiConfig" lib/l10n', null],
		["rg -g '*.arb' settingsAiConfig lib", null],
		['rg -n "pending fetch" AGENTS.md', null],
		['rg -n "has_active_credential_role" backend', "has_active_credential_role"],
		['rg -n "currentMembership" lib # literal: provider wiring', null],
		["rg season lib", null],
	];
	let failed = 0;
	for (const [command, expected] of cases) {
		const got = decide(command)?.symbol ?? null;
		const ok = got === expected;
		if (!ok) failed++;
		console.log(`${ok ? "ok  " : "FAIL"} ${command} → ${got} (want ${expected})`);
	}
	console.log(failed === 0 ? "self-test passed" : `${failed} failure(s)`);
	process.exit(failed === 0 ? 0 : 1);
}
