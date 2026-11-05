export const messages: Record<string, string> = {
  invalid_request: "입력 조건을 확인해 주세요.",
  unauthorized: "익명 이용 세션을 다시 연결해 주세요.",
  disabled: "추천 기능을 준비하고 있어요.",
  daily_limit: "오늘의 추천 횟수를 모두 사용했어요.",
  budget_limit: "서비스 이용 한도에 도달했어요.",
  in_progress: "이 추천을 처리하고 있어요.",
  expired: "추천 요청이 만료되었어요. 새 추천을 시작해 주세요.",
  conflict: "같은 요청의 입력 조건이 달라졌어요.",
  timeout:
    "추천 처리 결과를 확인할 수 없어요. 같은 요청의 상태를 확인해 주세요.",
  rate_limited: "잠시 뒤 같은 요청의 상태를 확인해 주세요.",
  unavailable: "추천 서비스를 잠시 이용할 수 없어요.",
  configuration: "추천 서비스를 준비하고 있어요.",
  invalid_output: "조건에 맞는 추천을 확인하지 못했어요.",
  not_found: "발급된 추천 요청을 찾을 수 없어요.",
};
const statuses: Record<string, number> = {
  invalid_request: 400,
  unauthorized: 401,
  disabled: 503,
  daily_limit: 429,
  budget_limit: 429,
  in_progress: 409,
  expired: 410,
  conflict: 409,
  timeout: 504,
  rate_limited: 429,
  unavailable: 503,
  configuration: 503,
  invalid_output: 502,
  not_found: 404,
};
export class RecipeError extends Error {
  code: string;
  status: number;
  retryable: boolean;
  retryAt?: string;
  constructor(code: string, retryAt?: string) {
    super(messages[code] ?? messages.unavailable);
    this.code = messages[code] ? code : "unavailable";
    this.status = statuses[this.code] ?? 503;
    this.retryable = [
      "in_progress",
      "rate_limited",
      "unavailable",
      "timeout",
    ].includes(this.code);
    this.retryAt = retryAt;
  }
}
export function safeError(error: unknown): RecipeError {
  return error instanceof RecipeError ? error : new RecipeError("unavailable");
}
export function errorBody(error: RecipeError) {
  return {
    error: {
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      ...(error.retryAt ? { retry_at: error.retryAt } : {}),
    },
  };
}
