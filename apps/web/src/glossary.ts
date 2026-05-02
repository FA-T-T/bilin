import type { GlossaryTerm } from "./api/types";

const protectedInlinePattern = /(`[^`]*`|\$\$.*?\$\$|\$[^$]*\$)/gs;

export function activeGlossaryTerms(terms: GlossaryTerm[] = []) {
  return terms.filter((term) => term.status === "active" && term.target_term.trim().length > 0);
}

export function applyGlossaryToMarkdown(markdown: string, terms: GlossaryTerm[] = []) {
  const activeTerms = activeGlossaryTerms(terms);
  if (activeTerms.length === 0) return markdown;
  return markdown
    .split(protectedInlinePattern)
    .map((chunk, index) => {
      if (index % 2 === 1) return chunk;
      return applyGlossaryToPlainText(chunk, activeTerms);
    })
    .join("");
}

function applyGlossaryToPlainText(text: string, terms: GlossaryTerm[]) {
  return [...terms]
    .sort((left, right) => right.source_term.length - left.source_term.length)
    .reduce((current, term) => {
      const sources = replacementSources(term);
      return sources.reduce((rendered, source) => {
        if (!source) return rendered;
        const flags = term.metadata?.case_sensitive ? "g" : "gi";
        const pattern = new RegExp(`(?<![\\w-])${escapeRegExp(source)}(?![\\w-])`, flags);
        return rendered.replace(pattern, term.target_term);
      }, current);
    }, text);
}

function replacementSources(term: GlossaryTerm) {
  const previous = term.metadata?.previous_target_terms;
  const previousTerms = Array.isArray(previous)
    ? previous.filter((item): item is string => typeof item === "string")
    : [];
  return [term.source_term, ...previousTerms];
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
