/**
 * Mock for lightning/platformShowToastEvent used in LWC Jest tests.
 */
export { ShowToastEventName } from 'lightning/platformShowToastEvent';
export class ShowToastEvent extends CustomEvent {
    constructor(toast) {
        super('lightning__showtoast', { detail: toast });
    }
}
