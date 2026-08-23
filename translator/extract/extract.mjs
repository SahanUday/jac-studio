import ts from "typescript";
import { readFileSync } from "node:fs";
import { basename } from "node:path";

function getLeadingDocComment(node, sourceFile) {
  const jsDocs = ts.getJSDocCommentsAndTags(node);
  if (jsDocs.length === 0) return "";
  return jsDocs.map((d) => d.getText(sourceFile)).join("\n");
}

function extractImports(sourceFile) {
  const imports = [];
  sourceFile.forEachChild((node) => {
    if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier)) {
      const names = [];
      const clause = node.importClause;
      if (clause?.namedBindings && ts.isNamedImports(clause.namedBindings)) {
        for (const el of clause.namedBindings.elements) names.push(el.name.text);
      }
      if (clause?.name) names.push(clause.name.text);
      imports.push({ from: node.moduleSpecifier.text, names });
    }
  });
  return imports;
}

function isExported(node) {
  const mods = ts.getCombinedModifierFlags(node);
  return (mods & ts.ModifierFlags.Export) !== 0;
}

function variableDeclarationKind(declarationList) {
  const flags = declarationList.flags;
  if (flags & ts.NodeFlags.Const) return "const";
  if (flags & ts.NodeFlags.Let) return "let";
  return "var";
}

function extractSymbols(sourceFile) {
  const symbols = [];
  sourceFile.forEachChild((node) => {
    if (!isExported(node)) return;
    if (ts.isClassDeclaration(node) && node.name) {
      const members = node.members
        .filter((m) => ts.isMethodDeclaration(m) || ts.isPropertyDeclaration(m))
        .map((m) => ({
          name: m.name?.getText(sourceFile) ?? "",
          kind: ts.isMethodDeclaration(m) ? "method" : "property",
          signature: m.getText(sourceFile).split("{")[0].trim(),
          doc: getLeadingDocComment(m, sourceFile),
        }));
      symbols.push({ kind: "class", name: node.name.text, doc: getLeadingDocComment(node, sourceFile), members });
    } else if (ts.isFunctionDeclaration(node) && node.name) {
      symbols.push({ kind: "function", name: node.name.text, doc: getLeadingDocComment(node, sourceFile), signature: node.getText(sourceFile).split("{")[0].trim() });
    } else if (ts.isInterfaceDeclaration(node)) {
      symbols.push({ kind: "interface", name: node.name.text, doc: getLeadingDocComment(node, sourceFile), signature: node.getText(sourceFile).split("{")[0].trim() });
    } else if (ts.isTypeAliasDeclaration(node)) {
      symbols.push({ kind: "type", name: node.name.text, doc: getLeadingDocComment(node, sourceFile), signature: node.getText(sourceFile) });
    } else if (ts.isEnumDeclaration(node)) {
      symbols.push({ kind: "enum", name: node.name.text, doc: getLeadingDocComment(node, sourceFile), signature: node.getText(sourceFile) });
    } else if (ts.isVariableStatement(node)) {
      const kind = variableDeclarationKind(node.declarationList);
      for (const decl of node.declarationList.declarations) {
        symbols.push({ kind, name: decl.name.getText(sourceFile), doc: getLeadingDocComment(node, sourceFile), signature: decl.getText(sourceFile) });
      }
    }
  });
  return symbols;
}

function extractOne(path) {
  const text = readFileSync(path, "utf8");
  const sourceFile = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true);
  return { path, basename: basename(path), imports: extractImports(sourceFile), symbols: extractSymbols(sourceFile) };
}

function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error("usage: extract.mjs <source.ts> [test.ts]");
    process.exit(2);
  }
  const result = { source: extractOne(args[0]) };
  if (args[1]) result.test = extractOne(args[1]);
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}

main();
