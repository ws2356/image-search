/**
 * Strip @property rules that use syntax: "*" — these are Tailwind v4 internal
 * CSS Houdini declarations for web transitions.  lightningcss (used by
 * react-native-css) does not support syntax: "*" and will throw a parse error.
 * React Native ignores CSS transitions entirely, so these can be removed safely.
 */
function stripUnsupportedAtProperty() {
  return {
    postcssPlugin: "strip-unsupported-at-property",
    AtRule: {
      property(node) {
        const syntaxDecl = node.nodes?.find(
          (n) => n.type === "decl" && n.prop === "syntax"
        );
        if (syntaxDecl?.value === '"*"') {
          node.remove();
        }
      },
    },
  };
}
stripUnsupportedAtProperty.postcss = true;

/**
 * Replace pathological radius values from Tailwind `.rounded-full`:
 *   1) calc(infinity * 1px)
 *   2) 3.40282e38px (max-float form emitted after optimization)
 * lightningcss/react-native-css cannot deserialize these on native, so clamp
 * them to a large finite radius.
 */
function replaceInfinityValues() {
  return {
    postcssPlugin: "replace-infinity-values",
    Declaration(decl) {
      decl.value = decl.value
        .replace(/calc\(\s*infinity\s*\*\s*[\d.]+px\s*\)/gi, "9999px")
        .replace(/\b3\.40282e(?:\+)?38px\b/gi, "9999px");
    },
  };
}
replaceInfinityValues.postcss = true;

/**
 * Strip @layer ordering statements (e.g. `@layer theme;`, `@layer properties;`).
 * These are web-only layer-ordering hints emitted by Tailwind v4.
 * React Native does not use CSS cascade layers, so removing them is safe.
 */
function stripLayerStatements() {
  return {
    postcssPlugin: "strip-layer-statements",
    AtRule: {
      layer(node) {
        // A layer-statement has no child nodes (no `{…}` block).
        if (!node.nodes) {
          node.remove();
        }
      },
    },
  };
}
stripLayerStatements.postcss = true;

export default {
  plugins: [
    "@tailwindcss/postcss",
    stripUnsupportedAtProperty,
    replaceInfinityValues,
    stripLayerStatements,
  ],
};
