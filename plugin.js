// @thaiannguyen-05/opencode-rules
//
// On-demand rule injection plugin for opencode.
// When user says "follow the rule of andev" (or similar), fetches RULES.md
// from GitHub and injects it into the system prompt.
//
// Hooks:
//   - chat.message: detect trigger phrase in user input
//   - experimental.chat.system.transform: inject rules into system prompt

const RULES_URL = 'https://raw.githubusercontent.com/thaiannguyen-05/rules-for-global-agents/main/RULES.md';

// Trigger patterns — case-insensitive
const TRIGGER_PATTERNS = [
  /follow\s+(the\s+)?rules?\s+of\s+andev/i,
  /follow\s+andev\s+rules?/i,
  /use\s+andev\s+rules?/i,
  /apply\s+andev\s+rules?/i,
  /andev\s+rules/i,
];

// In-memory cache: rules text per session
let cachedRules = null;
let fetchFailed = false;

function detectTrigger(text) {
  if (!text) return false;
  return TRIGGER_PATTERNS.some((pattern) => pattern.test(text));
}

async function fetchRules() {
  // Return cache if available
  if (cachedRules !== null) return cachedRules;

  // Don't retry if fetch already failed
  if (fetchFailed) return null;

  try {
    const response = await fetch(RULES_URL, {
      headers: { Accept: 'text/plain' },
    });

    if (!response.ok) {
      fetchFailed = true;
      return null;
    }

    const text = await response.text();

    if (!text || text.trim().length === 0) {
      fetchFailed = true;
      return null;
    }

    cachedRules = text;
    return cachedRules;
  } catch {
    fetchFailed = true;
    return null;
  }
}

export const AndevRulesPlugin = async (_ctx) => {
  let triggerDetected = false;

  return {
    // Detect trigger phrase in user messages
    'chat.message': async (_input, output) => {
      if (!output || !output.parts) return;

      for (const part of output.parts) {
        if (part && part.type === 'text' && part.text) {
          if (detectTrigger(part.text)) {
            triggerDetected = true;
          }
        }
      }
    },

    // Inject rules into system prompt when trigger was detected
    'experimental.chat.system.transform': async (_input, output) => {
      if (!output || !Array.isArray(output.system)) return;
      if (!triggerDetected) return;

      const rules = await fetchRules();
      if (rules) {
        output.system.push(`## Rules from andev (follow these rules)\n\n${rules}`);
      }

      // Reset trigger for next message
      triggerDetected = false;
    },
  };
};

export default AndevRulesPlugin;
