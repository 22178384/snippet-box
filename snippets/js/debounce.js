/**
 * debounce and throttle, written out so I stop importing lodash for two
 * functions.
 *
 * debounce: run once, after the calls stop. Good for search-as-you-type.
 * throttle: run at most once per interval. Good for scroll/resize handlers.
 *
 * Plain ESM, no dependencies. Node 18+ or any modern browser.
 *
 * Run the demo:  node debounce.js
 */

import { pathToFileURL } from "node:url";

/**
 * @param {Function} fn
 * @param {number} wait - milliseconds of quiet required before firing
 * @param {{leading?: boolean, trailing?: boolean}} [opts]
 * @returns {Function & {cancel: () => void, flush: () => void}}
 */
export function debounce(fn, wait, { leading = false, trailing = true } = {}) {
  let timer = null;
  let lastArgs = null;
  let lastThis = null;

  function invoke() {
    timer = null;
    if (trailing && lastArgs) {
      fn.apply(lastThis, lastArgs);
      lastArgs = lastThis = null;
    }
  }

  function debounced(...args) {
    lastArgs = args;
    lastThis = this;

    const callNow = leading && timer === null;
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(invoke, wait);

    if (callNow) {
      fn.apply(this, args);
      // Don't also fire on the trailing edge for this burst.
      lastArgs = lastThis = null;
    }
  }

  // Let callers bail out or force the pending call, which is the thing that
  // makes debounce usable in tests and in unmount handlers.
  debounced.cancel = () => {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    lastArgs = lastThis = null;
  };
  debounced.flush = () => {
    if (timer !== null) {
      clearTimeout(timer);
      invoke();
    }
  };

  return debounced;
}

/**
 * @param {Function} fn
 * @param {number} interval - minimum ms between invocations
 * @param {{leading?: boolean, trailing?: boolean}} [opts]
 */
export function throttle(fn, interval, { leading = true, trailing = true } = {}) {
  let lastCall = 0;
  let timer = null;
  let lastArgs = null;
  let lastThis = null;

  function debounced(...args) {
    const now = Date.now();
    if (!lastCall && !leading) lastCall = now;
    const remaining = interval - (now - lastCall);

    lastArgs = args;
    lastThis = this;

    if (remaining <= 0 || remaining > interval) {
      if (timer !== null) {
        clearTimeout(timer);
        timer = null;
      }
      lastCall = now;
      fn.apply(this, args);
      lastArgs = lastThis = null;
    } else if (timer === null && trailing) {
      timer = setTimeout(() => {
        lastCall = leading ? Date.now() : 0;
        timer = null;
        if (lastArgs) {
          fn.apply(lastThis, lastArgs);
          lastArgs = lastThis = null;
        }
      }, remaining);
    }
  }

  debounced.cancel = () => {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    lastCall = 0;
    lastArgs = lastThis = null;
  };

  return debounced;
}

// --- demo -------------------------------------------------------------------
// Guarded so importing the file (e.g. from a test) doesn't spam stdout.
// pathToFileURL is needed because on Windows import.meta.url is
// "file:///F:/..." while process.argv[1] is "F:\\..." — a naive string
// comparison never matches there.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const log = debounce((msg) => console.log("[debounced]", msg), 200);
  log("a");
  log("b");
  log("c"); // only this one fires, 200ms after the last call

  const tick = throttle((n) => console.log("[throttled]", n), 300);
  let i = 0;
  const handle = setInterval(() => tick(++i), 100);
  setTimeout(() => clearInterval(handle), 1000);

  setTimeout(() => {
    log.cancel(); // no-op here, but shows the API
    console.log("done");
  }, 1500);
}
