//! Offline heuristics for naming a note from its content.

const STOPWORDS: &[&str] = &[
    "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for", "with", "is", "are",
    "was", "were", "be", "been", "this", "that", "these", "those", "it", "its", "as", "at", "by",
    "from", "into", "about", "then", "than", "there", "here", "have", "has", "had", "not", "will",
    "would", "should", "could", "can", "just", "also", "very", "some", "when", "what", "which",
    "your", "yours", "their", "them", "they", "were", "does", "done", "over", "under", "more",
];

/// Suggest a filename-safe title for a note.
/// Priority: first meaningful line, then most frequent keywords, then a dated fallback.
pub fn suggest_name(content: &str) -> String {
    for line in content.lines() {
        let cleaned = clean_line(line);
        if cleaned.chars().count() >= 3 {
            return truncate_chars(&cleaned, 48);
        }
    }

    let keywords = top_keywords(content, 3);
    if !keywords.is_empty() {
        return keywords.join(" ");
    }

    format!("note {}", chrono::Local::now().format("%Y-%m-%d %H%M"))
}

/// Strip list markers, markdown headers and filename-unsafe characters.
fn clean_line(line: &str) -> String {
    let trimmed = line
        .trim_start_matches(|c: char| {
            c.is_whitespace() || matches!(c, '#' | '-' | '*' | '>' | '+' | '.' | ')' | '(')
                || c.is_ascii_digit()
        })
        .trim();

    let mut out = String::with_capacity(trimmed.len());
    let mut last_space = false;
    for c in trimmed.chars() {
        if c.is_alphanumeric() || matches!(c, '-' | '_' | '\'') {
            out.push(c);
            last_space = false;
        } else if !last_space && !out.is_empty() {
            out.push(' ');
            last_space = true;
        }
    }
    out.trim().to_string()
}

fn truncate_chars(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let cut: String = s.chars().take(max).collect();
    // Cut at the last word boundary so names do not end mid-word
    match cut.rfind(' ') {
        Some(i) if i > max / 2 => cut[..i].to_string(),
        _ => cut,
    }
}

fn top_keywords(content: &str, count: usize) -> Vec<String> {
    use std::collections::HashMap;
    let mut freq: HashMap<String, (usize, usize)> = HashMap::new();
    let mut order = 0usize;
    for word in content.split(|c: char| !c.is_alphanumeric()) {
        let w = word.to_lowercase();
        if w.chars().count() < 4 || STOPWORDS.contains(&w.as_str()) {
            continue;
        }
        let entry = freq.entry(w).or_insert((0, order));
        entry.0 += 1;
        order += 1;
    }
    let mut items: Vec<(String, usize, usize)> =
        freq.into_iter().map(|(w, (n, o))| (w, n, o)).collect();
    // Most frequent first, ties broken by first appearance
    items.sort_by(|a, b| b.1.cmp(&a.1).then(a.2.cmp(&b.2)));
    items.into_iter().take(count).map(|(w, _, _)| w).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_first_line() {
        assert_eq!(suggest_name("Shopping list\nmilk\neggs"), "Shopping list");
    }

    #[test]
    fn strips_markdown_and_unsafe_chars() {
        assert_eq!(suggest_name("# My: <great> plan!"), "My great plan");
    }

    #[test]
    fn skips_blank_and_short_lines() {
        assert_eq!(suggest_name("\n--\nMeeting notes for Q3"), "Meeting notes for Q3");
    }

    #[test]
    fn falls_back_to_keywords() {
        let name = suggest_name("!!! ???\n@@@");
        assert!(name.starts_with("note "));
    }

    #[test]
    fn truncates_long_lines_at_word_boundary() {
        let long = "word ".repeat(30);
        let name = suggest_name(&long);
        assert!(name.chars().count() <= 48);
        assert!(!name.ends_with(' '));
    }
}
