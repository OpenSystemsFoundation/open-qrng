/**
 * Shared utility for subscribing to QRNG Platform Events.
 * Centralizes event subscription lifecycle management to avoid
 * duplicate logic across qrngJobMonitor and qrngJobStatusPanel.
 *
 * Usage:
 *   import { subscribeToQRNGEvents, unsubscribeFromQRNGEvents } from 'c/qrngEventSubscription';
 *
 *   connectedCallback() {
 *       this._sub = subscribeToQRNGEvents(
 *           (completeEvent) => this.handleComplete(completeEvent),
 *           (failedEvent) => this.handleFailed(failedEvent)
 *       );
 *   }
 *   disconnectedCallback() {
 *       unsubscribeFromQRNGEvents(this._sub);
 *   }
 */
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

const COMPLETE_CHANNEL = '/event/OpenSF__QRNG_Complete__e';
const FAILED_CHANNEL = '/event/OpenSF__QRNG_Failed__e';

let _errorHandlerRegistered = false;

/**
 * Subscribe to QRNG Platform Events (Complete and Failed).
 * @param {Function} onComplete - callback for QRNG_Complete__e events
 * @param {Function} onFailed - callback for QRNG_Failed__e events (optional)
 * @returns {Object} subscription handle with .complete and .failed properties
 */
export function subscribeToQRNGEvents(onComplete, onFailed) {
    const handle = { complete: null, failed: null };

    if (!_errorHandlerRegistered) {
        onError((error) => {
            console.error('empApi error:', error);
        });
        _errorHandlerRegistered = true;
    }

    if (onComplete) {
        subscribe(COMPLETE_CHANNEL, -1, (message) => {
            onComplete(message);
        }).then((sub) => {
            handle.complete = sub;
        });
    }

    if (onFailed) {
        subscribe(FAILED_CHANNEL, -1, (message) => {
            onFailed(message);
        }).then((sub) => {
            handle.failed = sub;
        });
    }

    return handle;
}

/**
 * Unsubscribe from QRNG Platform Events.
 * @param {Object} handle - subscription handle from subscribeToQRNGEvents
 */
export function unsubscribeFromQRNGEvents(handle) {
    if (handle) {
        if (handle.complete) {
            unsubscribe(handle.complete);
            handle.complete = null;
        }
        if (handle.failed) {
            unsubscribe(handle.failed);
            handle.failed = null;
        }
    }
}
