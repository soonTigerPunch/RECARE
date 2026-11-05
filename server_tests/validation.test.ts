import test from "node:test";
import assert from "node:assert/strict";

const loaded = await import(
  "../supabase/functions/recipe-recommendations/validation.ts"
).catch(() => ({}));
const { validateRequest, validateOutput } = loaded as any;
export const requestFixture = () => ({
  request_id: "8493dd2f-5fa0-4a97-9629-acf94a0a3881",
  ingredients: [
    { id: "i0", name: "두부", amount: 300000, unit: "G", days_left: 0 },
  ],
  staples: [],
  servings: 1,
  max_minutes: 20,
  allow_shopping: false,
  exclusions: "",
});
export const recipeFixture = () => ({
  title: "두부 구이",
  servings: 1,
  minutes: 15,
  reason: "임박한 두부를 활용해요",
  ingredients: [
    {
      source_id: "i0",
      name: "두부",
      amount: 150000,
      unit: "G",
      display_quantity: "150 g",
      kind: "inventory",
    },
  ],
  steps: ["두부를 충분히 익혀요"],
  warnings: ["재료 상태와 익힘을 확인하세요"],
});
export const outputFixture = () => ({
  status: "ok",
  message: "",
  recipes: [recipeFixture()],
});

test("validation module exposes server boundary", () =>
  assert.equal(typeof validateRequest, "function"));
test("request admits integer stock and returns a clean normalized copy", () => {
  const input = requestFixture();
  assert.deepEqual(validateRequest(input), input);
});
test("request rejects sensitive and model-selection fields instead of forwarding them", () => {
  for (const key of ["food_ids", "price", "history", "model", "instructions"])
    assert.throws(() =>
      validateRequest({ ...requestFixture(), [key]: "secret" }),
    );
});
test("request rejects invalid quantities, unknown units, duplicate ids and expired stocks", () => {
  for (const fields of [
    { amount: 0 },
    { amount: 1.5 },
    { amount: 1000000000001 },
    { unit: "OZ" },
    { days_left: -1 },
    { id: "local-database-id" },
  ]) {
    const x = requestFixture();
    Object.assign(x.ingredients[0], fields);
    assert.throws(() => validateRequest(x));
  }
  const x = requestFixture();
  x.ingredients.push(x.ingredients[0]);
  assert.throws(() => validateRequest(x));
});
test("request bounds ingredients, servings, minutes, staples and exclusion length", () => {
  for (const fields of [
    { ingredients: [] },
    { ingredients: Array(11).fill(requestFixture().ingredients[0]) },
    { servings: 5 },
    { max_minutes: 15 },
    { staples: ["마늘"] },
    { exclusions: "가".repeat(201) },
  ])
    assert.throws(() => validateRequest({ ...requestFixture(), ...fields }));
});
test("output accepts inventory within same unit family without scaling base amounts", () => {
  const out = outputFixture();
  out.recipes[0].ingredients[0].unit = "KG";
  assert.equal(validateOutput(out, requestFixture()).recipes.length, 1);
});
test("output rejects forged ids, cross-family units, amount overflow and zero", () => {
  for (const fields of [
    { source_id: "i9" },
    { unit: "ML" },
    { amount: 300001 },
    { amount: 0 },
    { amount: 150000.5 },
    { name: "달걀" },
  ]) {
    const x = outputFixture();
    Object.assign(x.recipes[0].ingredients[0], fields);
    assert.throws(() => validateOutput(x, requestFixture()));
  }
});
test("output aggregates repeated inventory amounts before comparing with stock", () => {
  const x = outputFixture();
  x.recipes[0].ingredients.push({
    ...x.recipes[0].ingredients[0],
    amount: 200000,
  });
  assert.throws(() => validateOutput(x, requestFixture()));
});
test("output disallows unconfirmed staples and undisclosed staple instructions", () => {
  const x = outputFixture();
  x.recipes[0].ingredients.push({
    source_id: null,
    name: "간장",
    amount: null,
    unit: null,
    display_quantity: "약간",
    kind: "staple",
  } as any);
  assert.throws(() => validateOutput(x, requestFixture()));
  const y = outputFixture();
  y.recipes[0].steps = ["간장을 넣어요"];
  assert.throws(() => validateOutput(y, requestFixture()));
});
test("output permits only confirmed staples and at most three distinct shopping items", () => {
  const req = requestFixture();
  req.staples = ["소금"];
  const x = outputFixture();
  x.recipes[0].ingredients.push({
    source_id: null,
    name: "소금",
    amount: null,
    unit: null,
    display_quantity: "약간",
    kind: "staple",
  } as any);
  assert.equal(validateOutput(x, req).recipes.length, 1);
  x.recipes[0].ingredients.push({
    source_id: null,
    name: "파",
    amount: 1000,
    unit: "G",
    display_quantity: "1 g",
    kind: "shopping",
  } as any);
  assert.throws(() => validateOutput(x, req));
  req.allow_shopping = true;
  assert.equal(validateOutput(x, req).recipes.length, 1);
  for (const name of ["마늘", "양파", "당근"])
    x.recipes[0].ingredients.push({
      source_id: null,
      name,
      amount: null,
      unit: null,
      display_quantity: "약간",
      kind: "shopping",
    } as any);
  assert.throws(() => validateOutput(x, req));
});
test("output excludes obvious allergens and known compound-sauce ingredients", () => {
  const req = requestFixture();
  req.exclusions = "대두";
  assert.throws(() => validateOutput(outputFixture(), req));
  const req2 = requestFixture();
  req2.exclusions = "밀";
  req2.staples = ["간장"];
  const x = outputFixture();
  x.recipes[0].ingredients.push({
    source_id: null,
    name: "간장",
    amount: null,
    unit: null,
    display_quantity: "약간",
    kind: "staple",
  } as any);
  assert.throws(() => validateOutput(x, req2));
});
test("output returns valid subset and removes title-only duplicate dishes", () => {
  const x = outputFixture();
  const duplicate = recipeFixture();
  duplicate.title = "맛있는 두부";
  const invalid = recipeFixture();
  invalid.ingredients[0].amount = 999999;
  x.recipes.push(duplicate, invalid);
  assert.equal(validateOutput(x, requestFixture()).recipes.length, 1);
});
test("no_match cannot contain recipes and recipe needs stock, limits and warnings", () => {
  assert.deepEqual(
    validateOutput(
      { status: "no_match", message: "조건에 맞는 요리가 없어요", recipes: [] },
      requestFixture(),
    ).recipes,
    [],
  );
  for (const fields of [
    { servings: 2 },
    { minutes: 21 },
    { warnings: [] },
    { ingredients: [] },
  ]) {
    const x = outputFixture();
    Object.assign(x.recipes[0], fields);
    assert.throws(() => validateOutput(x, requestFixture()));
  }
  assert.throws(() =>
    validateOutput(
      { ...outputFixture(), status: "no_match" },
      requestFixture(),
    ),
  );
});
test("unit values must be actual strings rather than property-key-coercible arrays", () => {
  for (const unit of [["G"], ["KG"], null, {}, 1]) {
    const req = requestFixture();
    Object.assign(req.ingredients[0], { unit });
    assert.throws(() => validateRequest(req));
    const out = outputFixture();
    Object.assign(out.recipes[0].ingredients[0], { unit });
    assert.throws(() => validateOutput(out, requestFixture()));
  }
});
test("numeric display quantities are generated from validated integer base amounts", () => {
  const out = outputFixture();
  out.recipes[0].ingredients[0].display_quantity = "300 kg";
  assert.equal(
    validateOutput(out, requestFixture()).recipes[0].ingredients[0]
      .display_quantity,
    "150 g",
  );
  out.recipes[0].ingredients[0].unit = "KG";
  assert.equal(
    validateOutput(out, requestFixture()).recipes[0].ingredients[0]
      .display_quantity,
    "0.15 kg",
  );
  const req = requestFixture();
  req.allow_shopping = true;
  out.recipes[0].ingredients.push({
    source_id: null,
    name: "달걀",
    amount: 1500,
    unit: "PIECE",
    display_quantity: "999개",
    kind: "shopping",
  } as any);
  assert.equal(
    validateOutput(out, req).recipes[0].ingredients[1].display_quantity,
    "1.5 개",
  );
});

test("undeclared egg and garlic in prose cannot bypass purchase restrictions", () => {
  const out = outputFixture();
  out.recipes[0].steps = ["달걀 2개를 풀어 두부에 입힌 뒤 마늘과 함께 익혀요"];
  assert.throws(() => validateOutput(out, requestFixture()));
  const request = requestFixture();
  request.allow_shopping = true;
  for (const name of ["달걀", "마늘"])
    out.recipes[0].ingredients.push({
      source_id: null,
      name,
      amount: null,
      unit: null,
      display_quantity: "약간",
      kind: "shopping",
    } as any);
  assert.equal(validateOutput(out, request).recipes.length, 1);
});
