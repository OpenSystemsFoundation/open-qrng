import { reduceErrors, setupHiDpiCanvas } from 'c/qrngUtils';

describe('qrngUtils.reduceErrors', () => {
    it('returns plain strings as-is', () => {
        expect(reduceErrors('plain error')).toBe('plain error');
    });

    it('extracts body.message from Apex errors', () => {
        expect(reduceErrors({ body: { message: 'Apex failed' } })).toBe(
            'Apex failed'
        );
    });

    it('joins array bodies with semicolons', () => {
        expect(
            reduceErrors({
                body: [{ message: 'first' }, { message: 'second' }]
            })
        ).toBe('first; second');
    });

    it('skips array body entries without messages', () => {
        expect(reduceErrors({ body: [{ message: 'only' }, {}, null] })).toBe(
            'only'
        );
    });

    it('falls back to error.message', () => {
        expect(reduceErrors(new Error('js error'))).toBe('js error');
        expect(reduceErrors({ message: 'msg' })).toBe('msg');
    });

    it('uses statusText when no message', () => {
        expect(reduceErrors({ statusText: 'Server Error' })).toBe(
            'Server Error'
        );
    });

    it('never returns raw JSON for unknown shapes', () => {
        expect(reduceErrors({ x: 1 })).toBe('An unexpected error occurred.');
        expect(reduceErrors({ x: 1 })).not.toContain('{');
    });

    it('handles null/undefined/empty string', () => {
        expect(reduceErrors(null)).toBe('An unexpected error occurred.');
        expect(reduceErrors(undefined)).toBe('An unexpected error occurred.');
        expect(reduceErrors('')).toBe('An unexpected error occurred.');
    });

    it('handles empty array body with fallback to message', () => {
        expect(reduceErrors({ body: [], message: 'outer' })).toBe('outer');
    });
});

describe('qrngUtils.setupHiDpiCanvas', () => {
    let canvas;
    let mockCtx;

    beforeEach(() => {
        mockCtx = {
            setTransform: jest.fn(),
            scale: jest.fn()
        };
        canvas = document.createElement('canvas');
        canvas.getContext = jest.fn().mockReturnValue(mockCtx);
    });

    afterEach(() => {
        delete window.devicePixelRatio;
    });

    it('scales the backing store by devicePixelRatio', () => {
        window.devicePixelRatio = 2;
        const ctx = setupHiDpiCanvas(canvas, 300, 150);
        expect(canvas.width).toBe(600);
        expect(canvas.height).toBe(300);
        expect(canvas.style.width).toBe('300px');
        expect(canvas.style.height).toBe('150px');
        expect(ctx.setTransform).toHaveBeenCalledWith(2, 0, 0, 2, 0, 0);
    });

    it('defaults to dpr 1 when devicePixelRatio is undefined', () => {
        setupHiDpiCanvas(canvas, 300, 150);
        expect(canvas.width).toBe(300);
        expect(canvas.height).toBe(150);
        expect(mockCtx.setTransform).toHaveBeenCalledWith(1, 0, 0, 1, 0, 0);
    });

    it('falls back to ctx.scale when setTransform is unavailable', () => {
        window.devicePixelRatio = 2;
        delete mockCtx.setTransform;
        setupHiDpiCanvas(canvas, 100, 100);
        expect(mockCtx.scale).toHaveBeenCalledWith(2, 2);
    });

    it('returns null gracefully when no 2d context', () => {
        canvas.getContext = jest.fn().mockReturnValue(null);
        expect(setupHiDpiCanvas(canvas, 100, 100)).toBeNull();
    });
});
