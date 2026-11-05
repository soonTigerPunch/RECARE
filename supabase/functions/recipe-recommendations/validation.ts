import { RecipeError } from "./errors.ts";
export const staples = ["소금", "설탕", "식용유", "간장", "후추", "참기름"];
export const unitFamilies: Record<string, string> = {
  G: "weight",
  KG: "weight",
  ML: "volume",
  L: "volume",
  PIECE: "count",
};
export type Stock = {
  id: string;
  name: string;
  amount: number;
  unit: string;
  days_left: number;
};
export type RecipeRequest = {
  request_id: string;
  ingredients: Stock[];
  staples: string[];
  servings: number;
  max_minutes: number | null;
  allow_shopping: boolean;
  exclusions: string;
};
export type Ingredient = {
  source_id: string | null;
  name: string;
  amount: number | null;
  unit: string | null;
  display_quantity: string;
  kind: "inventory" | "staple" | "shopping";
};
export type Recipe = {
  title: string;
  servings: number;
  minutes: number;
  reason: string;
  ingredients: Ingredient[];
  steps: string[];
  warnings: string[];
};
export type RecipeOutput = {
  status: "ok" | "no_match";
  message: string;
  recipes: Recipe[];
};
export function uuid(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}
function object(value: unknown): value is Record<string, any> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function exact(
  value: unknown,
  keys: string[],
): asserts value is Record<string, any> {
  if (
    !object(value) ||
    Object.keys(value).length !== keys.length ||
    !keys.every((k) => Object.hasOwn(value, k))
  )
    throw new RecipeError("invalid_request");
}
function text(value: unknown, max: number, empty = false): value is string {
  return (
    typeof value === "string" &&
    value.length <= max &&
    (empty || value.trim().length > 0) &&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value)
  );
}
function integer(value: unknown, min: number, max: number): value is number {
  return (
    Number.isSafeInteger(value) && Number(value) >= min && Number(value) <= max
  );
}
const norm = (v: string) =>
  v
    .normalize("NFKC")
    .toLocaleLowerCase("ko")
    .replace(/[\s\p{P}\p{S}]/gu, "");
export function validateRequest(value: unknown): RecipeRequest {
  exact(value, [
    "request_id",
    "ingredients",
    "staples",
    "servings",
    "max_minutes",
    "allow_shopping",
    "exclusions",
  ]);
  if (
    !uuid(value.request_id) ||
    !Array.isArray(value.ingredients) ||
    value.ingredients.length < 1 ||
    value.ingredients.length > 10 ||
    !Array.isArray(value.staples) ||
    value.staples.length > 6 ||
    !integer(value.servings, 1, 4) ||
    ![null, 10, 20, 30].includes(value.max_minutes) ||
    typeof value.allow_shopping !== "boolean" ||
    !text(value.exclusions, 200, true)
  )
    throw new RecipeError("invalid_request");
  const ids = new Set(),
    groups = new Set();
  const ingredients = value.ingredients.map((s: unknown) => {
    exact(s, ["id", "name", "amount", "unit", "days_left"]);
    if (
      typeof s.id !== "string" ||
      !/^i[0-9]$/.test(s.id) ||
      ids.has(s.id) ||
      !text(s.name, 60) ||
      s.name !== s.name.trim() ||
      !integer(s.amount, 1, 1_000_000_000_000) ||
      typeof s.unit !== "string" ||
      !Object.hasOwn(unitFamilies, s.unit) ||
      !integer(s.days_left, 0, 36500)
    )
      throw new RecipeError("invalid_request");
    const group = s.name.normalize("NFC") + ":" + unitFamilies[s.unit];
    if (groups.has(group)) throw new RecipeError("invalid_request");
    ids.add(s.id);
    groups.add(group);
    return {
      id: s.id,
      name: s.name.normalize("NFC"),
      amount: s.amount,
      unit: s.unit,
      days_left: s.days_left,
    };
  });
  if (
    value.staples.some(
      (s: unknown) => typeof s !== "string" || !staples.includes(s),
    ) ||
    new Set(value.staples).size !== value.staples.length
  )
    throw new RecipeError("invalid_request");
  return {
    request_id: value.request_id.toLowerCase(),
    ingredients,
    staples: [...value.staples],
    servings: value.servings,
    max_minutes: value.max_minutes,
    allow_shopping: value.allow_shopping,
    exclusions: value.exclusions,
  };
}
function displayQuantity(amount: number, unit: string): string {
  const factor = unit === "KG" || unit === "L" ? 1000000 : 1000;
  const whole = Math.floor(amount / factor),
    remainder = amount % factor;
  const fraction = remainder
    ? "." +
      String(remainder)
        .padStart(factor === 1000000 ? 6 : 3, "0")
        .replace(/0+$/, "")
    : "";
  const label: Record<string, string> = {
    G: "g",
    KG: "kg",
    ML: "ml",
    L: "L",
    PIECE: "개",
  };
  return String(whole) + fraction + " " + label[unit];
}
const allergens: Record<string, string[]> = {
  대두: ["대두", "콩", "두부", "간장", "된장", "고추장", "쌈장", "soy", "tofu"],
  콩: ["콩", "대두", "두부", "간장", "된장", "고추장", "쌈장", "soy", "tofu"],
  밀: ["밀", "간장", "고추장", "쌈장", "빵", "면", "wheat", "flour"],
  땅콩: ["땅콩", "peanut"],
  우유: ["우유", "치즈", "버터", "크림", "milk", "cheese", "butter"],
  달걀: ["달걀", "계란", "마요네즈", "egg", "mayonnaise"],
  계란: ["계란", "달걀", "마요네즈", "egg", "mayonnaise"],
  참깨: ["참깨", "참기름", "깨", "sesame"],
  갑각류: ["새우", "게", "굴소스", "shrimp", "crab"],
};
function excluded(value: string, exclusions: string): boolean {
  const target = norm(value);
  return exclusions
    .split(/[,;\n·]+/u)
    .map((s) => norm(s.trim()))
    .filter(Boolean)
    .some((term) =>
      (allergens[term] ?? [term]).some((word) => target.includes(norm(word))),
    );
}
function validateRecipe(value: unknown, request: RecipeRequest): Recipe {
  exact(value, [
    "title",
    "servings",
    "minutes",
    "reason",
    "ingredients",
    "steps",
    "warnings",
  ]);
  if (
    !text(value.title, 100) ||
    value.servings !== request.servings ||
    !integer(value.minutes, 1, request.max_minutes ?? 240) ||
    !text(value.reason, 400) ||
    !Array.isArray(value.ingredients) ||
    value.ingredients.length < 1 ||
    value.ingredients.length > 24 ||
    !Array.isArray(value.steps) ||
    value.steps.length < 1 ||
    value.steps.length > 15 ||
    !value.steps.every((s) => text(s, 1000)) ||
    !Array.isArray(value.warnings) ||
    value.warnings.length < 1 ||
    value.warnings.length > 6 ||
    !value.warnings.every((s) => text(s, 400))
  )
    throw new RecipeError("invalid_output");
  const used = new Map<string, number>(),
    shopping = new Set(),
    declared = new Set();
  let inventory = 0;
  const ingredients = value.ingredients.map((i: unknown) => {
    exact(i, [
      "source_id",
      "name",
      "amount",
      "unit",
      "display_quantity",
      "kind",
    ]);
    if (
      !text(i.name, 60) ||
      !text(i.display_quantity, 100) ||
      !["inventory", "staple", "shopping"].includes(i.kind)
    )
      throw new RecipeError("invalid_output");
    declared.add(norm(i.name));
    if (i.kind === "inventory") {
      const stock = request.ingredients.find((s) => s.id === i.source_id);
      if (
        !stock ||
        norm(i.name) !== norm(stock.name) ||
        !integer(i.amount, 1, 1_000_000_000_000) ||
        typeof i.unit !== "string" ||
        !Object.hasOwn(unitFamilies, i.unit) ||
        unitFamilies[i.unit] !== unitFamilies[stock.unit]
      )
        throw new RecipeError("invalid_output");
      const amount = (used.get(stock.id) ?? 0) + i.amount;
      if (amount > stock.amount) throw new RecipeError("invalid_output");
      used.set(stock.id, amount);
      inventory++;
    } else {
      if (
        i.source_id !== null ||
        !(
          (i.amount === null && i.unit === null) ||
          (integer(i.amount, 1, 1_000_000_000_000) &&
            typeof i.unit === "string" &&
            Object.hasOwn(unitFamilies, i.unit))
        )
      )
        throw new RecipeError("invalid_output");
      if (i.kind === "staple" && !request.staples.includes(i.name))
        throw new RecipeError("invalid_output");
      if (i.kind === "shopping") {
        if (!request.allow_shopping) throw new RecipeError("invalid_output");
        shopping.add(norm(i.name));
      }
    }
    if (excluded(i.name, request.exclusions))
      throw new RecipeError("invalid_output");
    return {
      ...i,
      display_quantity:
        i.amount === null
          ? i.display_quantity
          : displayQuantity(i.amount, i.unit),
    } as Ingredient;
  });
  if (!inventory || shopping.size > 3) throw new RecipeError("invalid_output");
  const instructions = [value.title, ...value.steps].join(" ");
  if (excluded(instructions, request.exclusions))
    throw new RecipeError("invalid_output");
  // Conservative known-food checks; arbitrary prose cannot prove ingredient completeness.
  const foodWords = [
    "달걀",
    "계란",
    "마늘",
    "양파",
    "대파",
    "쪽파",
    "생강",
    "우유",
    "버터",
    "치즈",
    "밀가루",
    "전분",
    "고추장",
    "된장",
    "굴소스",
    "마요네즈",
    "케첩",
    "식초",
    "올리브유",
    "참깨",
    "땅콩",
    "새우",
    "돼지고기",
    "소고기",
    "닭고기",
    "감자",
    "당근",
    "애호박",
    "버섯",
    "김치",
    "두부",
    "고춧가루",
    "설탕",
    "소금",
    "간장",
    "참기름",
    "후추",
  ];
  const aliases: Record<string, string[]> = {
    달걀: ["달걀", "계란"],
    계란: ["달걀", "계란"],
  };
  for (const word of foodWords) {
    if (
      instructions.includes(word) &&
      !ingredients.some((i) =>
        (aliases[word] ?? [word]).some((alias) => i.name.includes(alias)),
      )
    )
      throw new RecipeError("invalid_output");
  }
  for (const staple of staples)
    if (
      norm(instructions).includes(norm(staple)) &&
      !declared.has(norm(staple))
    )
      throw new RecipeError("invalid_output");
  return {
    title: value.title,
    servings: value.servings,
    minutes: value.minutes,
    reason: value.reason,
    ingredients,
    steps: [...value.steps],
    warnings: [...value.warnings],
  };
}
export function validateOutput(
  value: unknown,
  request: RecipeRequest,
): RecipeOutput {
  try {
    exact(value, ["status", "message", "recipes"]);
    if (
      !text(value.message, 500, true) ||
      !Array.isArray(value.recipes) ||
      value.recipes.length > 3 ||
      !["ok", "no_match"].includes(value.status)
    )
      throw new RecipeError("invalid_output");
    if (value.status === "no_match") {
      if (value.recipes.length || !value.message.trim())
        throw new RecipeError("invalid_output");
      return { status: "no_match", message: value.message, recipes: [] };
    }
    const titles = new Set(),
      signatures = new Set();
    const recipes: Recipe[] = [];
    for (const candidate of value.recipes) {
      try {
        const recipe = validateRecipe(candidate, request);
        const title = norm(recipe.title);
        const sig =
          JSON.stringify(
            recipe.ingredients
              .map((i) => [i.kind, i.source_id, norm(i.name), i.amount])
              .sort(),
          ) + norm(recipe.steps.join(""));
        if (titles.has(title) || signatures.has(sig)) continue;
        titles.add(title);
        signatures.add(sig);
        recipes.push(recipe);
      } catch {
        /* Invalid candidates never enter the validated result. */
      }
    }
    if (!recipes.length) throw new RecipeError("invalid_output");
    const score = (recipe: Recipe) =>
      recipe.ingredients
        .filter((i) => i.kind === "inventory")
        .reduce(
          (n, i) =>
            n +
            1 /
              (1 +
                (request.ingredients.find((s) => s.id === i.source_id)
                  ?.days_left ?? 36500)),
          0,
        );
    recipes.sort(
      (a, b) =>
        score(b) - score(a) ||
        a.ingredients.filter((i) => i.kind === "shopping").length -
          b.ingredients.filter((i) => i.kind === "shopping").length ||
        a.minutes - b.minutes,
    );
    return { status: "ok", message: value.message, recipes };
  } catch {
    throw new RecipeError("invalid_output");
  }
}
