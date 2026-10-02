// The server owns time (docs/SERVER_PLAN.md). Tests replace the clock (in whole seconds).
let testClock: (() => number) | null = null;

export function nowUnix(): number {
  return testClock ? testClock() : Math.floor(Date.now() / 1000);
}

export function nowMs(): number {
  return testClock ? testClock() * 1000 : Date.now();
}

export function setClockForTests(fn: (() => number) | null): void {
  testClock = fn;
}
