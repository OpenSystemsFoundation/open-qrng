/**
 * Shared utility service module for QuantumFair LWCs.
 * No template — exports pure functions only.
 */

/**
 * Reduce any Apex / wire / JS error shape into a single user-friendly
 * message string. Never returns raw JSON.
 *
 * Handles:
 *  - plain strings
 *  - UI API / Apex errors ({ body: { message } })
 *  - array bodies ({ body: [{ message }, ...] })
 *  - JS errors ({ message })
 *  - anything else → generic fallback
 *
 * @param {*} error - the caught error
 * @returns {string} human-readable message
 */
const FALLBACK_MESSAGE = 'An unexpected error occurred.';

export function reduceErrors(error) {
    if (error == null) {
        return FALLBACK_MESSAGE;
    }
    if (typeof error === 'string') {
        return error || FALLBACK_MESSAGE;
    }
    if (Array.isArray(error.body)) {
        const messages = error.body
            .map((e) => e && e.message)
            .filter((m) => typeof m === 'string' && m.length > 0);
        if (messages.length > 0) {
            return messages.join('; ');
        }
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    if (typeof error.message === 'string' && error.message.length > 0) {
        return error.message;
    }
    if (typeof error.statusText === 'string' && error.statusText.length > 0) {
        return error.statusText;
    }
    return FALLBACK_MESSAGE;
}

/**
 * Size a canvas backing store for HiDPI (retina) displays.
 * Sets the backing store to cssWidth/cssHeight × devicePixelRatio,
 * keeps the CSS size at the logical dimensions, and returns a 2D
 * context whose transform is scaled so all drawing code can keep
 * using CSS-pixel coordinates.
 *
 * @param {HTMLCanvasElement} canvas - target canvas
 * @param {number} cssWidth - logical (CSS pixel) width
 * @param {number} cssHeight - logical (CSS pixel) height
 * @returns {CanvasRenderingContext2D|null} scaled 2D context
 */
export function setupHiDpiCanvas(canvas, cssWidth, cssHeight) {
    const dpr = (typeof window !== 'undefined' && window.devicePixelRatio) || 1;
    canvas.width = Math.round(cssWidth * dpr);
    canvas.height = Math.round(cssHeight * dpr);
    canvas.style.width = `${cssWidth}px`;
    canvas.style.height = `${cssHeight}px`;
    const ctx = canvas.getContext('2d');
    if (ctx) {
        if (typeof ctx.setTransform === 'function') {
            ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        } else if (typeof ctx.scale === 'function') {
            ctx.scale(dpr, dpr);
        }
    }
    return ctx;
}
