// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

/// Custom lint runner for breakdown_rs.
///
/// The `breakdown_lints` analyzer plugin uses `analysis_server_plugin`, which
/// only loads inside the analysis server (IDE/LSP mode) — not in the batch
/// `dart analyze` / `flutter analyze` CLI (see issue #299). This runner
/// re-implements the same four rules using the `analyzer` package directly,
/// so they can be enforced in CI without the plugin system.
///
/// Usage:
///   cd tool/breakdown_lints_runner
///   dart pub get
///   dart run bin/run_lints.dart ../..
///
/// Exits non-zero if any rule violations are found.
Future<void> main(List<String> args) async {
  final pathContext = PhysicalResourceProvider.INSTANCE.pathContext;
  final projectRoot = args.isNotEmpty
      ? pathContext.normalize(pathContext.absolute(args[0]))
      : // Default: the Flutter project root (parent of this tool package).
        pathContext.normalize(
          pathContext.absolute(
            pathContext.join(Directory.current.path, '..', '..'),
          ),
        );

  final collection = AnalysisContextCollection(
    includedPaths: ['$projectRoot/lib'],
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );

  final allErrors = <_LintError>[];
  for (final context in collection.contexts) {
    for (final filePath in context.contextRoot.analyzedFiles()) {
      if (!filePath.endsWith('.dart')) continue;
      if (filePath.contains('/vendor/breakdown_api/')) continue;

      final session = context.currentSession;
      final result = await session.getResolvedUnit(filePath);
      if (result is! ResolvedUnitResult) continue;

      for (final rule in _rules) {
        allErrors.addAll(rule.check(result));
      }
    }
  }

  if (allErrors.isEmpty) {
    stdout.writeln('breakdown_lints: no violations found.');
    exit(0);
  }

  // Sort by file, then line, then column for stable output.
  allErrors.sort((a, b) {
    var cmp = a.filePath.compareTo(b.filePath);
    if (cmp != 0) return cmp;
    cmp = a.line.compareTo(b.line);
    if (cmp != 0) return cmp;
    return a.column.compareTo(b.column);
  });

  for (final error in allErrors) {
    stderr.writeln(
      '${error.severity}\t${error.code}\t${error.filePath}:'
      '${error.line}:${error.column}\t${error.message}',
    );
  }

  stderr.writeln('\n${allErrors.length} breakdown_lints violation(s) found.');
  exit(1);
}

/// A single lint violation reported by a [_Runner].
class _LintError {
  _LintError({
    required this.code,
    required this.message,
    required this.severity,
    required this.filePath,
    required this.line,
    required this.column,
  });

  final String code;
  final String message;
  final String severity;
  final String filePath;
  final int line;
  final int column;
}

/// Base type for the four breakdown_rs rules re-implemented using the
/// `analyzer` package directly.
abstract class _Runner {
  List<_LintError> check(ResolvedUnitResult result);
}

final List<_Runner> _rules = [
  _DiscardResultRule(),
  _NoThrowInDataDomainRule(),
  _NoInsecureTlsRule(),
  _NoHardcodedSecretsRule(),
];

// ---------------------------------------------------------------------------
// Rule 1: discard_result
// ---------------------------------------------------------------------------

class _DiscardResultRule extends _Runner {
  @override
  List<_LintError> check(ResolvedUnitResult result) {
    final errors = <_LintError>[];
    final reporter = _LintErrorReporter(result, errors);
    result.unit.accept(_DiscardResultVisitor(reporter));
    return errors;
  }
}

class _DiscardResultVisitor extends RecursiveAstVisitor<void> {
  _DiscardResultVisitor(this.reporter);
  final _LintErrorReporter reporter;

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    final type = node.expression.staticType;
    if (type == null) return;
    if (_isFuture(type) || _isFpdartResultOrEither(type)) {
      reporter.report(
        node.expression,
        'discard_result',
        'Discarded result (Future / Result) must be handled.',
        'WARNING',
      );
    }
  }

  bool _isFuture(DartType type) {
    final element = type.element;
    if (element == null) return false;
    return element.name == 'Future' && element.library?.isDartAsync == true;
  }

  bool _isFpdartResultOrEither(DartType type) {
    final element = type.element;
    if (element == null) return false;
    final uri = element.library?.uri.toString() ?? '';
    if (!uri.contains('fpdart')) return false;
    if (element.name == 'Result' || element.name == 'Either') return true;
    if (type is InterfaceType) {
      for (final supertype in type.allSupertypes) {
        final supEl = supertype.element;
        final supUri = supEl.library.uri.toString();
        if (supUri.contains('fpdart') && supEl.name == 'Either') {
          return true;
        }
      }
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Rule 2: no_throw_in_data_domain
// ---------------------------------------------------------------------------

class _NoThrowInDataDomainRule extends _Runner {
  @override
  List<_LintError> check(ResolvedUnitResult result) {
    final path = result.path.replaceAll('\\', '/');
    if (!path.contains('/lib/data/') && !path.contains('/lib/domain/')) {
      return const [];
    }
    final errors = <_LintError>[];
    final reporter = _LintErrorReporter(result, errors);
    result.unit.accept(_NoThrowVisitor(reporter));
    return errors;
  }
}

class _NoThrowVisitor extends RecursiveAstVisitor<void> {
  _NoThrowVisitor(this.reporter);
  final _LintErrorReporter reporter;

  @override
  void visitThrowExpression(ThrowExpression node) {
    reporter.report(
      node,
      'no_throw_in_data_domain',
      'throw is forbidden in lib/data/** and lib/domain/**.',
      'WARNING',
    );
  }
}

// ---------------------------------------------------------------------------
// Rule 3: no_insecure_tls
// ---------------------------------------------------------------------------

class _NoInsecureTlsRule extends _Runner {
  @override
  List<_LintError> check(ResolvedUnitResult result) {
    final errors = <_LintError>[];
    final reporter = _LintErrorReporter(result, errors);
    result.unit.accept(_NoInsecureTlsVisitor(reporter));
    return errors;
  }
}

class _NoInsecureTlsVisitor extends RecursiveAstVisitor<void> {
  _NoInsecureTlsVisitor(this.reporter);
  final _LintErrorReporter reporter;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final lhs = node.leftHandSide;
    // The LHS can be either a PropertyAccess (e.g. `foo.bar = ...`) or
    // a PrefixedIdentifier (e.g. `client.badCertificateCallback = ...`).
    String? propertyName;
    if (lhs is PropertyAccess) {
      propertyName = lhs.propertyName.name;
    } else if (lhs is PrefixedIdentifier) {
      propertyName = lhs.identifier.name;
    }
    if (propertyName == 'badCertificateCallback' &&
        _returnsLiteralTrue(node.rightHandSide)) {
      reporter.report(
        node,
        'no_insecure_tls',
        'Insecure TLS configuration is forbidden.',
        'WARNING',
      );
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final classElement = node.constructorName.type.element;
    if (classElement?.name == 'SecurityContext') {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedArgument && arg.name.lexeme == 'allowInsecure') {
          final value = arg.argumentExpression;
          if (value is BooleanLiteral && value.value == true) {
            reporter.report(
              node,
              'no_insecure_tls',
              'Insecure TLS configuration is forbidden.',
              'WARNING',
            );
          }
        }
      }
    }
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == 'dangerouslyAllowInsecureCerts') {
      reporter.report(
        node,
        'no_insecure_tls',
        'Insecure TLS configuration is forbidden.',
        'WARNING',
      );
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'dangerouslyAllowInsecureCerts') {
      reporter.report(
        node,
        'no_insecure_tls',
        'Insecure TLS configuration is forbidden.',
        'WARNING',
      );
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    if (methodName != 'connect') return;
    final targetType = node.target?.staticType;
    final className = targetType?.element?.name;
    if (className != 'SecureSocket' && className != 'RawSecureSocket') {
      return;
    }
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument &&
          arg.name.lexeme == 'onBadCertificate' &&
          _returnsLiteralTrue(arg.argumentExpression)) {
        reporter.report(
          arg,
          'no_insecure_tls',
          'Insecure TLS configuration is forbidden.',
          'WARNING',
        );
      }
    }
  }

  bool _returnsLiteralTrue(Expression expression) {
    final body = switch (expression) {
      FunctionExpression(:final body) => body,
      _ => null,
    };
    if (body is ExpressionFunctionBody) {
      return body.expression is BooleanLiteral &&
          (body.expression as BooleanLiteral).value == true;
    }
    if (body is BlockFunctionBody) {
      for (final statement in body.block.statements) {
        if (statement is ReturnStatement &&
            statement.expression is BooleanLiteral &&
            (statement.expression as BooleanLiteral).value == true) {
          return true;
        }
      }
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Rule 4: no_hardcoded_secrets
// ---------------------------------------------------------------------------

class _NoHardcodedSecretsRule extends _Runner {
  @override
  List<_LintError> check(ResolvedUnitResult result) {
    final errors = <_LintError>[];
    final reporter = _LintErrorReporter(result, errors);
    result.unit.accept(_NoHardcodedSecretsVisitor(reporter));
    return errors;
  }
}

class _NoHardcodedSecretsVisitor extends RecursiveAstVisitor<void> {
  _NoHardcodedSecretsVisitor(this.reporter);
  final _LintErrorReporter reporter;

  static final _secretName = RegExp(
    r'(secret|token|password|passwd|api_?key|client_?secret|private_?key)',
    caseSensitive: false,
  );

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (value.isEmpty) return;
    final name = _surroundingName(node.parent);
    final nameLooksSecret = name != null && _secretName.hasMatch(name);
    if (nameLooksSecret && value.length >= 8) {
      reporter.report(
        node,
        'no_hardcoded_secrets',
        'Possible hardcoded secret detected.',
        'INFO',
      );
    }
  }

  String? _surroundingName(AstNode? parent) {
    final p = parent;
    if (p is VariableDeclaration) return p.name.lexeme;
    if (p is NamedArgument) return p.name.lexeme;
    if (p is FormalParameter) return p.name?.lexeme;
    if (p is AssignmentExpression) {
      final lhs = p.leftHandSide;
      if (lhs is SimpleIdentifier) return lhs.name;
      if (lhs is PropertyAccess) return lhs.propertyName.name;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Shared reporter helper
// ---------------------------------------------------------------------------

class _LintErrorReporter {
  _LintErrorReporter(this.result, this.errors);

  final ResolvedUnitResult result;
  final List<_LintError> errors;

  void report(AstNode node, String code, String message, String severity) {
    final location = result.lineInfo.getLocation(node.offset);
    errors.add(
      _LintError(
        code: code,
        message: message,
        severity: severity,
        filePath: result.path,
        line: location.lineNumber,
        column: location.columnNumber,
      ),
    );
  }
}
