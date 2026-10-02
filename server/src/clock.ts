// The server owns time (docs/SERVER_PLAN.md). Tests replace the clock.
let clock: () => number = () => Math.floor(Date.now() / 1000);

export function nowUnix(): number {
  return clock();
}

export function setClockForTests(fn: (() => number) | null): void {
  clock = fn ? fn : () => Math.floor(Date.now() / 1000);
}
