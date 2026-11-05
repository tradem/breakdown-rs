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
 * ## The second half: cold whole-file reads (P1)
 *
 * Text search was never the biggest drift. A 24 KB `read` of a 550-line screen
 * costs far more context than any `rg`, and it happens exactly when the agent
 * skipped the outline — yet no advisory covered it. So the same handler also
 * watches `read`: a COLD whole-file read (or a >= 400-line span) of a sizeable
 * code file inside an indexed project gets the file's symbol outline appended,
 * plus the calls that make the next question cheaper (`get_code_snippet`,
 * `trace_path`, `check_index_coverage`).
 *
 * "Cold" is stateful and per file: once a code-aware tool SUCCESSFULLY reported
 * on that path (`get_file_outline`, `search_graph`, `analyze_ast_map`, ...), the
 * read is not cold and nothing is appended — a FAILED lookup marks nothing,
 * because the model learned nothing from it. Small files (< 6 KB), targeted
 * reads (`offset`/`limit` under 400 lines), prose, test trees, generated
 * sources (`.g.dart`, `.freezed.dart`, `app_localizations*`) and anything
 * outside the project root are never annotated — a whole read of those IS the
 * right move.
 *
 * The declaration ROWS are printed only when the read itself was truncated: a
 * whole read under the read tool's 2000-line/50 KB cap already delivered those
 * declarations, so only the "use the outline next time" advice is added.
 *
 * Escape hatches: `PI_GRAPH_NUDGE=0` disables both halves for a session; a
 * `# literal:` marker disables the SEARCH half for that one call (a `read` has
 * no command, so a marker cannot suppress the read half).
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
 * Cost control: one `search_graph` per nudged call, plus — only for a
 * generated `<family>Provider` alias — TWO candidate lookups issued
 * CONCURRENTLY (wall time of one), plus at most one `trace_path`. Each CLI call
 * has a 4 s timeout and the stages run SEQUENTIALLY (`list_projects` when the
 * project cache is cold, `search_graph`, the concurrent retry pair, then
 * `trace_path`), so the worst reachable path is 4 × 4 s ≈ 16 s of added latency;
 * ~8 s applies only when the project cache is warm and no retry runs. There is
 * no overall deadline, so the bound is the sum of the per-call timeouts. The
 * cooldown, session cap and counters are RESERVED before the first await, so
 * concurrent sibling tool calls cannot overshoot them. A failed lookup appends
 * nothing. No network, read-only CLI calls, no index mutation.
 *
 * The read advisory has its own budget (one nudge per 45 s, 12 per session, one
 * `get_file_outline` per nudge, never on a path already annotated): a read of a
 * large file is itself expensive, so a 12-row outline beside it is cheap — and
 * when the outline lookup fails the block still carries the advice (never a
 * fabricated outline).
 */

import { statSync } from "node:fs";
import { posix } from "node:path";

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
	/(^|\/)(docs|openspec|vendor|node_modules|build|\.dart_tool|\.pi|\.github|\.codebase-memory)(\/|$)/;

/** Localization catalogs and generated l10n trees: key lookups are text lookups. */
const L10N_DIR_RE = /(^|\/)(l10n|i18n|locale|locales)(\/|$)/;

/** Files that carry code (tells an explicit FILE operand from a directory). */
const CODE_FILE_RE =
	/\.(dart|rs|ts|tsx|js|jsx|mjs|cjs|py|sql|kt|kts|swift|go|java|rb|php|cs|cc|cpp|c|h|hpp)$/i;

/** Test trees: a text search here is usually a fixture hunt, not an impact question. */
const TEST_DIR_RE = /(^|\/)(test|tests|integration_test)(\/|$)/;

const COOLDOWN_MS = 12_000;
const SESSION_CAP = 40;
const CLI_TIMEOUT_MS = 4_000;
const MAX_HITS = 3;
const MAX_CALLERS = 3;

/** Read-advisory budget: a cold whole-file read is expensive on its own. */
const READ_COOLDOWN_MS = 45_000;
const READ_SESSION_CAP = 12;
/** Below this a whole-file read is cheaper than an outline + snippet round trip. */
const READ_SIZE_THRESHOLD_BYTES = 6 * 1024;
/** A read asking for at least this many lines is a file discovery, not a lookup. */
const READ_SPAN_THRESHOLD_LINES = 400;
const MAX_OUTLINE_ROWS = 12;

/**
 * Tools whose result already told the model what is in a file. A read after one
 * of these is not "cold" — annotating it would be noise. Only tools that name a
 * PATH belong here: `get_code_snippet` takes a `qualified_name` and reports no
 * path at all, so listing it would mark nothing.
 */
const DISCOVERY_TOOLS = new Set([
	"get_file_outline",
	"search_graph",
	"search_code",
	"get_architecture",
	"trace_path",
	"query_graph",
	"analyze_ast_map",
	"analyze_ast_context",
	"analyze_ast_search",
	"analyze_ast_impact",
	"lsp_document_symbols",
]);

/**
 * Generated sources: a whole read is the normal move there (the file IS the
 * artifact, and its hand-written source is what carries meaning).
 */
const GENERATED_FILE_RE =
	/(\.(g|freezed|gr|chopper|mocks|config)\.dart$|app_localizations\w*\.dart$|\.g\.rs$)/;

/** Symbol shapes that make a text search a *meaning* question. */
const PASCAL_RE = /^[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+$/;
const CAMEL_RE = /^[a-z][a-z0-9]*(?:[A-Z][a-z0-9]*)+$/;
const SNAKE_RE = /^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/;
const CONST_RE = /^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$/;

/**
 * Glob flags: their value names files, so it is a *target* hint (`-g '*.arb'`
 * means a catalog search). A NEGATED glob (`-g '!*.arb'`) excludes files from a
 * code search and must not turn the search into a text search.
 */
const GLOB_FLAGS = new Set(["-g", "--glob", "--iglob"]);

/**
 * Flags whose value is neither the pattern nor a target hint (`-t dart`,
 * `-C 2`, `-m 5`). Their value is consumed and ignored — note that `-e` /
 * `--regexp` are deliberately NOT here: for `rg -e PATTERN`, the value IS the
 * pattern, so it must fall through to the positional handling below.
 */
const OTHER_VALUE_FLAGS = new Set([
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
	"-f",
	"--file",
]);

export type NudgeDecision = {
	/** The symbol-shaped token the search is about. */
	symbol: string;
	/** True for PascalCase — construction sites are not graph edges. */
	classLike: boolean;
	/** `cd`/`pushd` target the search runs in, when the command changed dir. */
	cwd?: string;
};

/** Strips one layer of surrounding quotes from one word. */
function unquoteWord(word: string): string {
	return word.replace(/^['"]|['"]$/g, "");
}

/** True when [root] contains [dir] on a path-COMPONENT boundary. */
function containsPath(dir: string, root: string): boolean {
	const normalized = root.replace(/\/+$/, "");
	return dir === normalized || dir.startsWith(`${normalized}/`);
}

/**
 * Expands brace alternatives in a glob (`*.{arb,md}` → `*.arb`, `*.md`).
 * Positive globs combine as a UNION of include patterns, so the text/code
 * question has to be asked per alternative — an end-anchored test on the raw
 * `…}` would read a text-only union as code.
 */
function expandBraces(glob: string): string[] {
	const match = /^(.*?)\{([^{}]*)\}(.*)$/.exec(glob);
	if (!match) return [glob];
	const head = match[1] ?? "";
	const body = match[2] ?? "";
	const tail = match[3] ?? "";
	return body
		.split(",")
		.flatMap((alternative) => expandBraces(`${head}${alternative.trim()}${tail}`));
}

const isSymbol = (token: string): boolean =>
	token.length >= 6 &&
	(PASCAL_RE.test(token) ||
		CAMEL_RE.test(token) ||
		SNAKE_RE.test(token) ||
		CONST_RE.test(token));

/**
 * Splits a shell command line into simple command segments.
 *
 * Quote-aware on purpose: a `;` or `|` INSIDE a quoted argument is data, not a
 * command separator. Without that, `echo '; rg Foo lib'` would be split into a
 * bogus `rg` segment and the advisory would attach to an `echo`. Anything this
 * cannot parse yields "no nudge", which is the safe direction.
 */
export type CommandSegment = {
	/** Whitespace-split words of this simple command. */
	words: string[];
	/** Separator run that IMMEDIATELY preceded it (`null` for the first). */
	after: string | null;
	/** Raw segment text, used to spot subshell parentheses. */
	text: string;
};

export function splitCommands(command: string): CommandSegment[] {
	const segments: { text: string; after: string | null }[] = [];
	let current = "";
	let pending: string | null = null;
	let quote: string | null = null;
	let escaped = false;
	for (const ch of command) {
		if (escaped) {
			current += ch;
			escaped = false;
			continue;
		}
		// A backslash is LITERAL inside single quotes (POSIX): `'\'` closes the
		// quote, it does not escape it, so `'\'; rg Foo lib` still splits.
		if (ch === "\\" && quote !== "'") {
			current += ch;
			escaped = true;
			continue;
		}
		if (quote !== null) {
			current += ch;
			if (ch === quote) quote = null;
			continue;
		}
		if (ch === '"' || ch === "'") {
			current += ch;
			quote = ch;
			continue;
		}
		if (ch === "|" || ch === ";" || ch === "\n" || ch === "&") {
			segments.push({ text: current, after: pending });
			// Only the separator run SINCE the last real command belongs to the next
			// segment: in `a | rg X; rg Y` the second search is not piped, and
			// reading an accumulated `|;` as "piped" would silence it.
			pending = current.trim() === "" ? (pending ?? "") + ch : ch;
			current = "";
			continue;
		}
		current += ch;
	}
	segments.push({ text: current, after: pending });
	const out: CommandSegment[] = [];
	for (const segment of segments) {
		const words = tokenize(segment.text);
		if (words.length === 0) continue;
		out.push({ words, after: segment.after, text: segment.text });
	}
	return out;
}

/**
 * Splits one command segment into words QUOTE-AWARE: whitespace separates words
 * only outside quotes, so `'release notes.md'` stays ONE operand. Quotes are
 * kept in the token; `unquote` strips them where it matters.
 */
function tokenize(text: string): string[] {
	const words: string[] = [];
	let current = "";
	let quote: string | null = null;
	let started = false;
	let escaped = false;
	for (const ch of text) {
		// A backslash escapes the NEXT character (outside single quotes), so
		// `release\ notes.md` stays ONE operand. Splitting there would hide the
		// `.md` suffix and read a text-file search as a code search.
		if (escaped) {
			current += ch;
			escaped = false;
			continue;
		}
		if (ch === "\\" && quote !== "'") {
			current += ch;
			escaped = true;
			started = true;
			continue;
		}
		if (quote !== null) {
			current += ch;
			if (ch === quote) quote = null;
			continue;
		}
		if (ch === '"' || ch === "'") {
			current += ch;
			quote = ch;
			started = true;
			continue;
		}
		if (ch === " " || ch === "\t" || ch === "\r") {
			if (started) {
				words.push(current);
				current = "";
				started = false;
			}
			continue;
		}
		current += ch;
		started = true;
	}
	if (started) words.push(current);
	return words;
}

/**
 * Decides whether a shell command is a text search that should be nudged.
 *
 * Returns `null` for everything that is not a symbol-shaped search over code —
 * including every case where `rg` is the correct tool.
 */
export function decide(command: string): NudgeDecision | null {
	if (command.includes("# literal:")) return null;

	const segments = splitCommands(command);
	// A leading `cd`/`pushd` moves the SEARCH directory, so the graph lookup must
	// follow it (otherwise another tree's symbols get labelled). Subshell forms
	// (`(cd …`, `{ cd …`, `$(cd …`) are recognised by stripping the opener.
	const unopened = (word: string) => word.replace(/^[({$]+/, "");
	const isCd = (words: string[]) => {
		const first = words.map(unopened).find((word) => word !== "") ?? "";
		return /^(cd|pushd)$/.test(first.replace(/^.*\//, ""));
	};
	let cdTarget: string | null = null;
	let nonCdBefore = false;
	for (const segment of segments) {
		if (isCd(segment.words)) {
			// Option operands are not the directory (`cd -P frontend-flutter`), and a
			// `cd` with NO directory operand (`cd`, `cd -P`) goes to `$HOME` / the
			// previous directory, which is not reconstructable from the command.
			const target = segment.words
				.slice(1)
				.map(unquoteWord)
				.find((word) => word !== "" && !word.startsWith("-"));
			if (target === undefined) return null;
			cdTarget = target;
			continue;
		}
		let k = 0;
		while (
			k < segment.words.length &&
			/^[A-Za-z_][A-Za-z0-9_]*=/.test(segment.words[k]!)
		) {
			k++;
		}
		const bin = segment.words[k]?.replace(/^.*\//, "");
		if (bin && SEARCH_COMMANDS.has(bin)) break;
		nonCdBefore = true;
	}

	// A `cd` inside a subshell that CLOSED before this search did not move the
	// directory the search runs in: in `(cd a && rg -F x lib); rg Y lib` the
	// second search runs in the original directory, so carrying `a` over would
	// label another tree's symbols.
	const closedSubshellBefore = (index: number): boolean =>
		segments
			.slice(0, index)
			.some((earlier) => earlier.text.includes(")"));

	for (let index = 0; index < segments.length; index++) {
		const { words, after } = segments[index]!;
		// Conditional separators: `A || rg …` runs only when A FAILED and
		// `A && rg …` only when A SUCCEEDED, so in both cases the search may
		// never have executed — and the appended block would annotate someone
		// else's output. Allowed: an unconditional separator (`;`, newline, `|`)
		// and an `&&` chain whose only preceding commands were `cd`/`pushd`
		// (the ubiquitous "change directory, then search" shape).
		const conditional = after !== null && /(\|\||&&)/.test(after);
		if (conditional) {
			// Only an `&&` chain qualifies: in `cd X || rg …` the search runs when the
			// `cd` FAILED, i.e. in the ORIGINAL directory, so the target is wrong.
			const isCdChain =
				cdTarget !== null && !nonCdBefore && !after.includes("||");
			if (!isCdChain) continue;
		}
		// `cd` somewhere else in the chain: the directory the search ran in is not
		// reconstructable, so stay silent.
		if (cdTarget !== null && nonCdBefore) continue;
		if (cdTarget !== null && closedSubshellBefore(index)) continue;
		// Skip leading env assignments (`FOO=1 rg …`).
		let i = 0;
		while (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i]!)) i++;
		const bin = words[i]?.replace(/^.*\//, "");
		if (!bin || !SEARCH_COMMANDS.has(bin)) continue;

		let pattern: string | null = null;
		// Every `-e`/`--regexp` value is an alternative pattern. A search with
		// more than one pattern is an alternation (a regex intent), not a
		// single-symbol question, so it is never nudged.
		const extraPatterns: string[] = [];
		// Once a `-e`/`--regexp` value supplied a pattern, every later positional
		// word is an OPERAND (`rg -e Foo lib` searches `lib` for `Foo`).
		let patternFromFlag = false;
		const unquote = (word: string) => word.replace(/^['"]|['"]$/g, "");
		// Glob values are TARGET hints; directory operands decide the scope.
		const globs: string[] = [];
		const operands: string[] = [];
		for (let j = i + 1; j < words.length; j++) {
			const word = words[j]!;
			if (word === "--") continue;
			if (word.startsWith("-")) {
				// Inline `--flag=value` must behave like the two-word form.
				const eq = word.indexOf("=");
				const name = eq === -1 ? word : word.slice(0, eq);
				const inline = eq === -1 ? null : word.slice(eq + 1);
				if (GLOB_FLAGS.has(name)) {
					const raw = inline ?? words[j + 1];
					if (inline === null) j++;
					const value = raw === undefined ? undefined : unquote(raw);
					// A negated glob EXCLUDES files from a code search; it is not a
					// text target (otherwise `-g '!*.arb'` would silently mute us).
					// Test the UNQUOTED value: `'!*.arb'` still starts with a quote.
					if (value !== undefined && !value.startsWith("!")) {
						globs.push(value);
					}
					continue;
				}
				if (name === "-e" || name === "--regexp") {
					// `rg -e PATTERN` / `rg --regexp=PATTERN`: the value IS a pattern.
					const raw = inline ?? words[j + 1];
					if (inline === null) j++;
					if (raw !== undefined) {
						extraPatterns.push(unquote(raw));
						patternFromFlag = true;
					}
					continue;
				}
				if (OTHER_VALUE_FLAGS.has(name) && inline === null) j++;
				continue;
			}
			if (pattern === null && !patternFromFlag) {
				pattern = word;
				continue;
			}
			operands.push(unquote(word));
		}

		// `cat notes.md | rg Symbol` reads STDIN, not the tree: with no file
		// operand after a pipe, `rg` searches the piped text and there is no code
		// search to annotate.
		const pipedIn = after !== null && after.includes("|") && !after.includes("||");
		if (pipedIn && operands.length === 0) continue;

		// Exactly ONE pattern across both spellings (`rg Foo`, `rg -e Foo`,
		// `rg -e a -e b`): an alternation is a regex intent, and a single graph
		// answer would misrepresent it.
		const allPatterns = [
			...(pattern === null ? [] : [unquote(pattern)]),
			...extraPatterns,
		];
		if (allPatterns.length !== 1) continue;

		// A quoted phrase or a regex is not a symbol lookup.
		const bare = allPatterns[0]!;
		if (!isSymbol(bare)) continue;

		// Positive globs are a UNION of include patterns, and an explicit FILE
		// operand is read regardless of them. So a text glob alone only proves a
		// text search when it is the ONLY way files can be reached:
		//   `rg -g '*.arb' X lib`              → text only → silent
		//   `rg -g '*.arb' -g '*.dart' X lib`  → the union includes code → nudge
		//   `rg -g '*.arb' X lib/a.dart`       → the file is read directly → nudge
		const explicitCodeFile = operands.some((operand) =>
			CODE_FILE_RE.test(operand),
		);
		const codeReachableByGlob = globs.some((glob) =>
			expandBraces(glob).some(
				(alternative) =>
					!TEXT_TARGET_RE.test(alternative) ||
					CODE_FILE_RE.test(alternative),
			),
		);
		if (globs.length > 0 && !codeReachableByGlob && !explicitCodeFile) {
			continue;
		}

		// Operands (dirs AND explicit files) are searched regardless of globs, so
		// the advisory is skipped only when EVERY operand is a text file or a
		// non-code tree: `rg X lib translations.arb` still searches code under
		// `lib`, while `rg X lib/l10n` or `rg X test` searches no code at all.
		const isNonCode = (p: string) =>
			TEXT_TARGET_RE.test(p) ||
			NON_CODE_DIR_RE.test(p) ||
			TEST_DIR_RE.test(p) ||
			L10N_DIR_RE.test(p);
		if (operands.length > 0 && operands.every(isNonCode)) continue;

		return {
			symbol: bare,
			classLike: PASCAL_RE.test(bare),
			...(cdTarget === null ? {} : { cwd: cdTarget }),
		};
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
			`(NAME-ONLY match on \`${matchedAs}\`; no code hit for \`${symbol}\` and no`,
		);
		out.push(
			` Riverpod annotation was verified — confirm whether \`${symbol}\` is a`,
		);
		out.push(` generated provider or simply not indexed)`);
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
		// The marker compares against the names actually LISTED, not against
		// MAX_CALLERS: provider-owned rows are dropped from the names, so the
		// engine total can exceed them without hitting the cap.
		const omitted = callers.total > callers.callers.length;
		out.push(`  inbound: ${callers.total}${list ? ` → ${list}` : ""}${omitted ? " …" : ""}`);
	}
	if (classLike) {
		out.push(
			`  construction sites are NOT graph edges (Dart classes report 0 inbound):`,
		);
		out.push(`  use \`analyze_ast_impact\` (ast-bro) for "who instantiates this".`);
	}
	return out.join("\n");
}

/** Absolute, normalized form of a tool's `path` argument. */
export function absPath(path: string, cwd: string): string {
	return posix.normalize(
		path.startsWith("/")
			? path
			: `${cwd.replace(/\/+$/, "")}/${path}`,
	);
}

/**
 * The path-only half of the read filter: is this a code file whose whole-read is
 * a *discovery* question at all? Pure and project-root-independent, so the
 * handler can drop prose/tests/generated reads BEFORE spending a `list_projects`
 * round trip on them.
 */
export function isReadCandidatePath(relish: string): boolean {
	if (!CODE_FILE_RE.test(relish)) return false;
	if (NON_CODE_DIR_RE.test(relish) || L10N_DIR_RE.test(relish)) return false;
	if (TEST_DIR_RE.test(relish) || GENERATED_FILE_RE.test(relish)) return false;
	return true;
}

/** What a cold whole-file read looks like once it passed every filter. */
export type ReadDecision = {
	/** Normalized absolute path — the per-session dedupe key. */
	abs: string;
	/** Repository-relative path — what the graph tools want. */
	relPath: string;
	/** File size in bytes (for the advisory text). */
	bytes: number;
};

/**
 * Decides whether a `read` call is a COLD file discovery that deserves the
 * outline advisory. Pure (the caller stats the file), so the self-test covers
 * it without a filesystem.
 *
 * Not a nudge (a whole read there is the right move): prose and config, test
 * trees, generated sources, anything outside the project root, small files, and
 * targeted reads (`offset`/`limit` well below [READ_SPAN_THRESHOLD_LINES]).
 */
export function decideRead(args: {
	path?: string;
	offset?: number | null;
	limit?: number | null;
	cwd: string;
	projectRoot: string;
	sizeBytes: number;
}): ReadDecision | null {
	if (!args.path) return null;
	const abs = absPath(args.path, args.cwd);
	const rel = posix.relative(posix.normalize(args.projectRoot), abs);
	// Outside the indexed project: nothing the graph could answer.
	if (rel.length === 0 || rel.startsWith("..") || rel.startsWith("/")) {
		return null;
	}
	if (!isReadCandidatePath(rel)) return null;
	if (args.sizeBytes < READ_SIZE_THRESHOLD_BYTES) return null;

	const offset = args.offset ?? null;
	const limit = args.limit ?? null;
	// `offset: 0` means "from the top", which is still a whole-file read.
	const wholeFile = (offset === null || offset === 0) && limit === null;
	const wideSpan = limit !== null && limit >= READ_SPAN_THRESHOLD_LINES;
	if (!wholeFile && !wideSpan) return null;

	return { abs: abs, relPath: rel, bytes: args.sizeBytes };
}

/**
 * The appended block for a cold whole-file read. Compact, and honest when the
 * outline lookup failed: the advice stands on its own, the rows are never
 * guessed.
 */
export function formatReadBlock(args: {
	project: string;
	relPath: string;
	bytes: number;
	rows: { name: string; label: string; lines: string }[];
	total: number;
	outlineFailed: boolean;
	/** The read was truncated, so its declaration rows are NEW information. */
	truncated: boolean;
	/** The full framing once per session, then the short form. */
	verbose?: boolean;
}): string {
	const {
		project,
		relPath,
		bytes,
		rows,
		total,
		outlineFailed,
		truncated,
		verbose,
	} = args;
	const kb = `${Math.round(bytes / 1024)} KB`;
	const out: string[] = [];
	out.push("");
	out.push(
		`── code-aware (codebase-memory · ${project}) ─────────────────────────`,
	);
	if (verbose) {
		out.push(
			`A whole-file read costs the file's full length; "what is in this file`,
		);
		out.push(
			`and what does it touch" is one outline plus two snippets — smaller the`,
		);
		out.push(
			`longer the file. Nothing here blocks the read; it just points at that path.`,
		);
	}
	out.push("");
	out.push(`• cold whole-file read: ${relPath} (${kb})`);
	if (outlineFailed) {
		out.push(
			`  outline unavailable right now — check freshness before trusting an empty`,
		);
		out.push(
			`  answer: \`scripts/check-graph-freshness.sh\`, then \`scripts/reindex-graph.sh --if-stale\`.`,
		);
	} else if (rows.length === 0) {
		out.push(
			`  the index has no declarations for this path — it may be new or excluded`,
		);
		out.push(
			`  (\`check_index_coverage\` answers that; \`vendor/\` is never indexed).`,
		);
	} else {
		out.push(
			`  next time: get_file_outline("${relPath}") → ${total} declaration${total === 1 ? "" : "s"}`,
		);
		// A whole read under the tool's cap already contained these
		// declarations; repeating them would be context for nothing.
		if (truncated) {
			for (const row of rows) {
				out.push(
					`    ${row.name.padEnd(22)} ${row.label.padEnd(9)} ${row.lines}`,
				);
			}
			if (total > rows.length) {
				out.push(`    (+${total - rows.length} more: get_file_outline)`);
			}
		}
	}
	// One call beats two: `search_code` answers "where is this / how connected"
	// with qn + line + in/out counts (the graph part of a discovery question);
	// `trace_path` adds caller NAMES, coverage adds the honest caveat. Verified
	// against `codebase-memory-mcp cli search_code` on this repo — 43 ms, and it
	// covers symbols AND literal keys, so one entry point replaces the probing.
	const example = rows.at(0)?.name;
	out.push(
		example
			? `  one call beats two: search_code("${example}") → qn + line + in/out`
			: `  one call for "where is this / who uses it": search_code("<symbol>")`
				+ ` → qn + line + in/out`,
	);
	out.push(
		`  then get_code_snippet(<qn>) for a body; \`trace_path\` inbound adds caller NAMES;`,
	);
	out.push(
		`  \`check_index_coverage\` before claiming "no other consumer".`,
	);
	out.push(
		`(one per cold file per session; PI_GRAPH_NUDGE=0 opts out)`,
	);
	return out.join("\n");
}

/**
 * Maps the `get_file_outline` envelope (`{cols, rows, total}`) into the rows the
 * read block prints. Tolerant on purpose: a shape change must degrade to fewer
 * rows, never to a thrown advisory.
 */
export function readOutlineRows(payload: unknown): {
	rows: { name: string; label: string; lines: string }[];
	total: number;
} {
	const p = payload as
		| { cols?: unknown; rows?: unknown; total?: unknown }
		| null
		| undefined;
	const cols = Array.isArray(p?.cols) ? (p!.cols as unknown[]) : [];
	const raw = Array.isArray(p?.rows) ? (p!.rows as unknown[][]) : [];
	const idx = (name: string) => cols.findIndex((c) => c === name);
	const iName = idx("name");
	const iLabel = idx("label");
	const iLines = idx("lines");
	const rows = raw
		.map((row) => {
			const cell = (i: number) =>
				i >= 0 && typeof row?.[i] === "string" ? (row[i] as string) : "";
			return {
				name: cell(iName),
				label: cell(iLabel),
				lines: cell(iLines),
			};
		})
		.filter((row) => row.name.length > 0);
	const total =
		typeof p?.total === "number" ? (p.total as number) : rows.length;
	return { rows, total };
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

/**
 * The directory a search ran in: the `cd` target joined onto the session cwd.
 *
 * `..`/`.` MUST be resolved here: `cd ../other && rg …` run from `/work/repo`
 * joins to `/work/repo/../other`, which `containsPath` would still read as
 * inside `/work/repo` — and the advisory would annotate the wrong project.
 */
export function searchDir(sessionCwd: string, target: string | undefined): string {
	const joined =
		target === undefined
			? sessionCwd
			: target.startsWith("/")
				? target
				: `${sessionCwd.replace(/\/+$/, "")}/${target}`;
	return posix.normalize(joined);
}

export default function graphFirstNudge(pi: ExtensionAPI): void {
	if (process.env.PI_GRAPH_NUDGE === "0") return;

	const bin = process.env.CODEBASE_MEMORY_BIN || DEFAULT_BIN;
	let lastNudgeAt = 0;
	let nudges = 0;
	// Keyed by directory: a single entry reused across trees would answer a
	// worktree search with another project's symbols (and a cached `null` from an
	// unindexed directory would mute the repository for a whole minute).
	type ProjectRef = { name: string; root: string };
	const projectCache = new Map<string, { value: ProjectRef | null; at: number }>();

	const resolveProjectRef = async (
		cwd: string,
		signal?: AbortSignal,
	): Promise<ProjectRef | null> => {
		const cached = projectCache.get(cwd);
		if (cached && Date.now() - cached.at < 60_000) {
			return cached.value;
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
			.filter((p) => typeof p.root_path === "string" && containsPath(cwd, p.root_path))
			.sort((a, b) => (b.root_path?.length ?? 0) - (a.root_path?.length ?? 0))[0];
		const value: ProjectRef | null =
			typeof match?.name === "string" && typeof match.root_path === "string"
				? { name: match.name, root: match.root_path }
				: null;
		// Bounded so a long session cannot grow it without limit.
		if (projectCache.size >= 8) projectCache.clear();
		projectCache.set(cwd, { value, at: Date.now() });
		return value;
	};

	const resolveProject = async (
		cwd: string,
		signal?: AbortSignal,
	): Promise<string | null> =>
		(await resolveProjectRef(cwd, signal))?.name ?? null;

	pi.on("tool_result", async (event, ctx) => {
		try {
			if (event.toolName !== "bash") return;
			const input = event.input as { command?: string } | undefined;
			const command = input?.command;
			if (!command) return;

			const decision = decide(command);
			if (!decision) return;

			// Cooldown + session cap: the nudge must stay cheap and welcome.
			// RESERVED before the first await — sibling `bash` calls from one
			// assistant message run concurrently, so a check-then-set would let
			// both pass and overshoot the budget.
			const now = Date.now();
			if (now - lastNudgeAt < COOLDOWN_MS) return;
			if (nudges >= SESSION_CAP) return;
			lastNudgeAt = now;
			const verbose = nudges === 0;
			nudges++;

			// The graph lookup must run in the directory the SEARCH ran in: a
			// `cd x && rg …` changes it, and annotating another tree's symbols
			// would be worse than staying silent.
			const cwd = searchDir(ctx.cwd, decision.cwd);
			const project = await resolveProject(cwd, ctx.signal);
			if (!project) return;

			const search = await graphCli(
				pi.exec.bind(pi),
				"search_graph",
				{ project, query: decision.symbol, limit: 30, format: "json" },
				{ cwd, signal: ctx.signal, bin },
			);
			// A failed/timed-out lookup appends NOTHING (the header promises silence):
			// `graphCli` returns null and "no hits" would otherwise be reported as
			// "no code symbol named …", i.e. a lie about a stale index.
			if (search === null) return;
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
				// PascalCase while the generated getter is camelCase — try both,
				// CONCURRENTLY so the wall time stays that of one lookup.
				const pascal = family.charAt(0).toUpperCase() + family.slice(1);
				const candidates = [family, pascal].filter(
					(candidate) => candidate.length >= 6 && isSymbol(candidate),
				);
				const results = await Promise.all(
					candidates.map((candidate) =>
						graphCli(
							pi.exec.bind(pi),
							"search_graph",
							{ project, query: candidate, limit: 30, format: "json" },
							{ cwd, signal: ctx.signal, bin },
						),
					),
				);
				for (let k = 0; k < candidates.length; k++) {
					const retryHits = collect(results[k], candidates[k]!);
					if (retryHits.length > 0) {
						hits = retryHits;
						matchedAs = candidates[k];
						break;
					}
				}
				// A FAILED candidate lookup (null) is not an empty index: staying
				// silent beats claiming the symbol does not exist.
				if (hits.length === 0 && results.some((result) => result === null)) {
					return;
				}
			}

			// Shape comes from the RESOLVED name: a camelCase `<family>Provider`
			// token that matched the hand-written `CurrentMembership` class is
			// class-like, so it gets the construction note instead of a trace.
			const resolved = matchedAs ?? decision.symbol;
			const classLike = PASCAL_RE.test(resolved);
			// Inbound edges only for a SINGLE function-like definition: with two
			// same-named definitions, `trace_path` (bare name) would attach one
			// definition's callers to the other's bullet.
			let callers: { total: number; callers: Caller[] } | undefined;
			if (!classLike && hits.length === 1) {
				const trace = await graphCli(
					pi.exec.bind(pi),
					"trace_path",
					{
						project,
						function_name: resolved,
						direction: "inbound",
						limit: 25,
						format: "json",
					},
					{ cwd, signal: ctx.signal, bin },
				);
				callers = pickCallers(trace);
			}

			const block = formatBlock({
				project,
				symbol: decision.symbol,
				hits,
				classLike,
				callers,
				matchedAs,
				verbose,
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

	// -----------------------------------------------------------------------
	// Read advisory (P1): a COLD whole-file read of a sizeable code file.
	//
	// Text search was never the expensive drift; a 24 KB `read` of a 550-line
	// screen is, and it happens exactly when the outline was skipped. "Cold" is
	// per file: the moment a code-aware tool reported on that path, later reads
	// of it are not annotated.
	//
	// Discovery tools report REPOSITORY-relative paths (that is what the graph
	// tools take), while `read` passes paths relative to the session cwd — which
	// is commonly a SUBDIRECTORY (`frontend-flutter/`). Every reported path is
	// therefore kept NORMALIZED and matched against all three shapes a read can
	// produce (cwd-relative, project-relative, absolute): one set hit each, never
	// a scan over every earlier tool call.
	// -----------------------------------------------------------------------
	const inspectedPaths = new Set<string>();
	const readNudged = new Set<string>();
	let lastReadNudgeAt = 0;
	let readNudges = 0;

	pi.on("tool_result", async (event, ctx) => {
		try {
			// Bookkeeping comes first: a discovery tool's result marks its file
			// as "already inspected", for the rest of the session. A FAILED call
			// marks nothing — it did not tell the model what is in that file.
			if (DISCOVERY_TOOLS.has(event.toolName)) {
				if (event.isError) return;
				const input = event.input as Record<string, unknown> | undefined;
				for (const key of ["file_path", "path"]) {
					const value = input?.[key];
					if (typeof value === "string" && value.length > 1) {
						inspectedPaths.add(posix.normalize(value));
					}
				}
				return;
			}
			if (event.toolName !== "read") return;
			// A failed read produced an error, not file contents: nothing to advise.
			if (event.isError) return;

			const input = event.input as
				| { path?: string; offset?: number | null; limit?: number | null }
				| undefined;
			if (!input?.path) return;

			const abs = absPath(input.path, ctx.cwd);
			if (readNudged.has(abs)) return;

			// Cheapest first: prose, test trees and generated sources are the
			// RIGHT whole-read, and deciding that must not cost a CLI call.
			const cwdRel = posix.relative(ctx.cwd, abs);
			if (!isReadCandidatePath(cwdRel)) return;

			// Stat BEFORE deciding: size is the "is this a file discovery"
			// signal. A missing file is an error the read tool already reports.
			let sizeBytes: number;
			try {
				sizeBytes = statSync(abs).size;
			} catch {
				return;
			}

			const project = await resolveProjectRef(ctx.cwd, ctx.signal);
			if (!project) return;

			const decision = decideRead({
				path: input.path,
				offset: input.offset ?? null,
				limit: input.limit ?? null,
				cwd: ctx.cwd,
				projectRoot: project.root,
				sizeBytes,
			});
			if (!decision) return;

			// A file whose outline a discovery tool already reported on is not
			// cold — annotating that read would be pure noise. The path may be
			// spelled relative to the cwd, to the project root, or absolute.
			if (
				inspectedPaths.has(cwdRel) ||
				inspectedPaths.has(decision.relPath) ||
				inspectedPaths.has(abs)
			) {
				return;
			}

			// Budget RESERVED before the await (sibling calls run concurrently).
			const now = Date.now();
			if (now - lastReadNudgeAt < READ_COOLDOWN_MS) return;
			if (readNudges >= READ_SESSION_CAP) return;
			lastReadNudgeAt = now;
			const verbose = readNudges === 0;
			readNudges++;
			readNudged.add(abs);

			// The graph runs in the SESSION cwd (the project root is only used to
			// relativize the path — `get_file_outline` wants repo-relative paths).
			const outline = await graphCli(
				pi.exec.bind(pi),
				"get_file_outline",
				{
					project: project.name,
					file_path: decision.relPath,
					limit: MAX_OUTLINE_ROWS,
					format: "json",
				},
				{ cwd: ctx.cwd, signal: ctx.signal, bin },
			);

			const parsed = readOutlineRows(outline);
			const block = formatReadBlock({
				project: project.name,
				relPath: decision.relPath,
				bytes: decision.bytes,
				rows: parsed.rows,
				total: parsed.total,
				outlineFailed: outline === null,
				// Only a truncated read left declarations unread.
				truncated: Boolean(
					(event.details as { truncation?: unknown } | undefined)
						?.truncation,
				),
				verbose,
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
	type Case = { cmd: string; symbol: string | null; cwd?: string };
	const cases: Case[] = [
		{ cmd: 'rg -n "currentMembershipProvider" lib', symbol: "currentMembershipProvider" },
		{ cmd: 'rg -n "AiConfigScreen" lib test', symbol: "AiConfigScreen" },
		{
			cmd: 'rg -n "has_active_credential_role" backend',
			symbol: "has_active_credential_role",
		},
		// Text search is the RIGHT tool here → no advisory.
		{ cmd: 'rg -n "transport\\." lib', symbol: null },
		{ cmd: 'rg -n "settingsAiConfig" lib/l10n', symbol: null },
		{ cmd: "rg -g '*.arb' settingsAiConfig lib", symbol: null },
		{ cmd: 'rg -n "pending fetch" AGENTS.md', symbol: null },
		{ cmd: "rg season lib", symbol: null },
		{ cmd: 'rg -n "currentMembership" lib # literal: provider wiring', symbol: null },
		// Quote-aware splitting: separators inside quotes are data.
		{ cmd: "echo '; rg currentMembershipProvider lib'", symbol: null },
		{ cmd: 'echo "rg currentMembershipProvider lib"', symbol: null },
		// A literal backslash inside single quotes does not escape the closer.
		{ cmd: "printf '%s' '\\'; rg currentMembershipProvider lib", symbol: "currentMembershipProvider" },
		// A quoted operand with a space stays ONE operand (text file → silent).
		{ cmd: "rg currentMembershipProvider 'release notes.md'", symbol: null },
		// …and so does a BACKSLASH-escaped space.
		{ cmd: "rg currentMembershipProvider release\\ notes.md", symbol: null },
		// A brace glob is a UNION of alternatives: text-only stays silent, one code
		// alternative is enough to nudge.
		{ cmd: "rg -g '*.{arb,md}' currentMembershipProvider lib", symbol: null },
		{
			cmd: "rg -g '*.{arb,dart}' currentMembershipProvider lib",
			symbol: "currentMembershipProvider",
		},
		// Piped input is not a tree search: `rg` with no file operand reads stdin.
		{ cmd: "cat release-notes.md | rg currentMembershipProvider", symbol: null },
		{
			cmd: "cat release-notes.md | rg currentMembershipProvider lib",
			symbol: "currentMembershipProvider",
		},
		// …but a LATER command after a pipe is not piped itself.
		{
			cmd: "cat notes.md | rg -F x; rg currentMembershipProvider lib",
			symbol: "currentMembershipProvider",
		},
		// Inline `--flag=value` and `-e`/`--regexp` spellings.
		{ cmd: "rg --glob='*.arb' currentMembershipProvider lib", symbol: null },
		// …but an explicit CODE FILE is read regardless of the glob.
		{
			cmd: "rg -g '*.arb' currentMembershipProvider lib/a.dart",
			symbol: "currentMembershipProvider",
		},
		// …and positive globs combine as a UNION: one code glob is enough.
		{
			cmd: "rg -g '*.arb' -g '*.dart' currentMembershipProvider lib",
			symbol: "currentMembershipProvider",
		},
		// Two text globs alone stay a text search.
		{ cmd: "rg -g '*.arb' -g '*.md' currentMembershipProvider lib", symbol: null },
		{ cmd: "rg -e currentMembershipProvider lib", symbol: "currentMembershipProvider" },
		{ cmd: "rg --regexp=aiConfigErrorCopy lib", symbol: "aiConfigErrorCopy" },
		// Two patterns are an alternation, not a single-symbol question.
		{ cmd: "rg -e '[0-9]+' -e currentMembershipProvider lib", symbol: null },
		// A negated glob excludes files; it does not make this a text search.
		{ cmd: "rg -g '!*.arb' currentMembershipProvider lib", symbol: "currentMembershipProvider" },
		// Mixed targets: a text operand next to code still searches code.
		{ cmd: "rg currentMembershipProvider lib translations.arb", symbol: "currentMembershipProvider" },
		{ cmd: "rg currentMembershipProvider test", symbol: null },
		{ cmd: "rg currentMembershipProvider docs", symbol: null },
		{ cmd: "rg currentMembershipProvider lib docs", symbol: "currentMembershipProvider" },
		// Non-glob flag values are not path hints (`-C 2`, `-t dart`).
		{ cmd: "rg -t dart -C 2 currentMembershipProvider lib", symbol: "currentMembershipProvider" },
		// Conditional separators: the search may never have run.
		{ cmd: "true || rg currentMembershipProvider lib", symbol: null },
		{ cmd: "false && rg currentMembershipProvider lib", symbol: null },
		// …except the ubiquitous "change directory, then search": the target is
		// carried so the graph lookup follows it.
		{ cmd: "cd /tmp && rg currentMembershipProvider lib", symbol: "currentMembershipProvider", cwd: "/tmp" },
		{ cmd: "cd frontend-flutter && rg currentMembershipProvider lib", symbol: "currentMembershipProvider", cwd: "frontend-flutter" },
		{ cmd: "(cd /tmp && rg currentMembershipProvider lib)", symbol: "currentMembershipProvider", cwd: "/tmp" },
		// `cd` options are not directories (`-P` is not a path).
		{
			cmd: "cd -P frontend-flutter && rg currentMembershipProvider lib",
			symbol: "currentMembershipProvider",
			cwd: "frontend-flutter",
		},
		// A `cd` with NO directory operand goes to $HOME: not reconstructable.
		{ cmd: "cd -P && rg currentMembershipProvider lib", symbol: null },
		// A subshell that already CLOSED did not move the search directory…
		{ cmd: "(cd frontend-flutter); rg currentMembershipProvider lib", symbol: null },
		{ cmd: "(cd a && rg -F x lib); rg currentMembershipProvider lib", symbol: null },
		// …and `cd X || rg …` runs the search only when the `cd` FAILED.
		{ cmd: "cd /tmp || rg currentMembershipProvider lib", symbol: null },
		// A `cd` after another command makes the search dir unreconstructable.
		{ cmd: "make && cd /tmp && rg currentMembershipProvider lib", symbol: null },
	];

	let failed = 0;
	for (const testCase of cases) {
		const decision = decide(testCase.cmd);
		const symbol = decision?.symbol ?? null;
		const cwd = decision?.cwd ?? null;
		const expectedCwd = testCase.cwd ?? null;
		const ok = symbol === testCase.symbol && cwd === expectedCwd;
		if (!ok) failed++;
		console.log(
			`${ok ? "ok  " : "FAIL"} ${testCase.cmd} → ${symbol}${cwd === null ? "" : ` @${cwd}`} (want ${testCase.symbol}${expectedCwd === null ? "" : ` @${expectedCwd}`})`,
		);
	}

	// The joined search directory must be NORMALIZED: `cd ../other` from
	// `/work/repo` is `/work/other`, not `/work/repo/../other` (which
	// `containsPath` would read as inside `/work/repo`).
	const dirCases: { sessionCwd: string; target?: string; want: string }[] = [
		{ sessionCwd: "/work/repo", target: "../other", want: "/work/other" },
		{ sessionCwd: "/work/repo", target: "./lib", want: "/work/repo/lib" },
		{
			sessionCwd: "/work/repo/",
			target: "frontend-flutter",
			want: "/work/repo/frontend-flutter",
		},
		{ sessionCwd: "/work/repo", target: undefined, want: "/work/repo" },
		{ sessionCwd: "/work/repo", target: "/tmp", want: "/tmp" },
	];
	for (const testCase of dirCases) {
		const got = searchDir(testCase.sessionCwd, testCase.target);
		const ok = got === testCase.want;
		if (!ok) failed++;
		console.log(
			`${ok ? "ok  " : "FAIL"} searchDir(${testCase.sessionCwd}, ${testCase.target ?? "—"}) → ${got} (want ${testCase.want})`,
		);
	}

	// The read advisory (P1): which reads are COLD file discoveries, and which
	// ones are the right move (prose, tests, generated, small, targeted, outside
	// the project).
	const ROOT = "/work/repo";
	const CWD = "/work/repo/frontend-flutter";
	const BIG = 24 * 1024;
	type ReadCase = {
		label: string;
		path?: string;
		offset?: number | null;
		limit?: number | null;
		cwd: string;
		projectRoot: string;
		sizeBytes: number;
		want: string | null;
	};
	const readCases: ReadCase[] = [
		{
			label: "cold whole read of a big screen (relative)",
			path: "lib/features/shell/app_shell.dart",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: "frontend-flutter/lib/features/shell/app_shell.dart",
		},
		{
			label: "cold whole read of a big screen (absolute)",
			path: `${CWD}/lib/features/shell/app_shell.dart`,
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: "frontend-flutter/lib/features/shell/app_shell.dart",
		},
		{
			label: "wide span read (limit 600) of a big file",
			path: "lib/features/shell/app_shell.dart",
			limit: 600,
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: "frontend-flutter/lib/features/shell/app_shell.dart",
		},
		{
			label: "offset: 0 from the top is still a whole-file read",
			path: "lib/features/shell/app_shell.dart",
			offset: 0,
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: "frontend-flutter/lib/features/shell/app_shell.dart",
		},
		{
			label: "targeted read (offset) is a lookup, not a discovery",
			path: "lib/features/shell/app_shell.dart",
			offset: 340,
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
		{
			label: "narrow span (limit 40) is a lookup",
			path: "lib/features/shell/app_shell.dart",
			limit: 40,
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
		{
			label: "small file below the threshold",
			path: "lib/features/shell/window_size_class.dart",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: 900,
			want: null,
		},
		{
			label: "prose is not code",
			path: "../docs/design/screens/script-view.md",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
		{
			label: "ARB catalog is text",
			path: "lib/l10n/app_de.arb",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
		{
			label: "test tree is a fixture hunt",
			path: "test/features/shell/app_shell_test.dart",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
		{
			label: "generated source IS the artifact",
			path: "lib/features/shell/shell_controller.g.dart",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
		{
			label: "outside the indexed project",
			path: "/tmp/scratch/notes.dart",
			cwd: CWD,
			projectRoot: ROOT,
			sizeBytes: BIG,
			want: null,
		},
	];
	for (const testCase of readCases) {
		const got = decideRead(testCase);
		const rel = got?.relPath ?? null;
		const ok = rel === testCase.want;
		if (!ok) failed++;
		console.log(
			`${ok ? "ok  " : "FAIL"} decideRead(${testCase.label}) → ${rel} (want ${testCase.want})`,
		);
	}

	// The appended block must degrade honestly: an outline envelope the CLI did
	// not answer (null) is reported, never rendered as "no declarations".
	const failedBlock = formatReadBlock({
		project: "breakdown-rs",
		relPath: "frontend-flutter/lib/a.dart",
		bytes: BIG,
		rows: [],
		total: 0,
		outlineFailed: true,
		truncated: false,
	});
	const failedOk =
		failedBlock.includes("outline unavailable") &&
		!failedBlock.includes("no declarations");
	if (!failedOk) failed++;
	console.log(`${failedOk ? "ok  " : "FAIL"} formatReadBlock(failed lookup)`);

	// …and a real envelope renders its rows with line ranges.
	const rows = readOutlineRows({
		cols: ["name", "label", "lines", "qn"],
		rows: [
			["AppShell", "Class", "95-108", "x.AppShell"],
			["AppShellState", "Class", "110-412", "x.AppShellState"],
		],
		total: 7,
	});
	const rowsOk =
		rows.rows.length === 2 &&
		rows.total === 7 &&
		rows.rows[0]?.name === "AppShell" &&
		rows.rows[1]?.lines === "110-412";
	if (!rowsOk) failed++;
	console.log(`${rowsOk ? "ok  " : "FAIL"} readOutlineRows(cols → rows)`);

	// Rows are only new information when the read was TRUNCATED: a whole read
	// under the tool's cap already carried every declaration it lists.
	const fullReadBlock = formatReadBlock({
		project: "breakdown-rs",
		relPath: "frontend-flutter/lib/a.dart",
		bytes: BIG,
		rows: rows.rows,
		total: rows.total,
		outlineFailed: false,
		truncated: false,
	});
	const truncatedBlock = formatReadBlock({
		project: "breakdown-rs",
		relPath: "frontend-flutter/lib/a.dart",
		bytes: BIG,
		rows: rows.rows,
		total: rows.total,
		outlineFailed: false,
		truncated: true,
	});
	const truncationOk =
		!fullReadBlock.includes("AppShellState") &&
		fullReadBlock.includes("next time: get_file_outline") &&
		truncatedBlock.includes("AppShellState") &&
		truncatedBlock.includes("+5 more");
	if (!truncationOk) failed++;
	console.log(
		`${truncationOk ? "ok  " : "FAIL"} formatReadBlock(rows only when truncated)`,
	);

	console.log(failed === 0 ? "self-test passed" : `${failed} failure(s)`);
	process.exit(failed === 0 ? 0 : 1);
}
