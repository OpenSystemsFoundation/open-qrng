// Mock empApi
const mockSubscribe = jest
    .fn()
    .mockImplementation(() => Promise.resolve({ id: 'sub-123' }));
const mockUnsubscribe = jest.fn();
const mockOnError = jest.fn();

jest.mock(
    'lightning/empApi',
    () => ({
        subscribe: mockSubscribe,
        unsubscribe: mockUnsubscribe,
        onError: mockOnError
    }),
    { virtual: true }
);

// Import after mocking
let subscribeToQuantumEvents, unsubscribeFromQuantumEvents;

describe('c-qrng-event-subscription', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        // Re-import to reset module state
        jest.resetModules();
        const mod = require('c/qrngEventSubscription');
        subscribeToQuantumEvents = mod.subscribeToQuantumEvents;
        unsubscribeFromQuantumEvents = mod.unsubscribeFromQuantumEvents;
    });

    it('subscribes to both Complete and Failed channels', async () => {
        const onComplete = jest.fn();
        const onFailed = jest.fn();

        subscribeToQuantumEvents(onComplete, onFailed);

        expect(mockSubscribe).toHaveBeenCalledTimes(2);
        expect(mockSubscribe).toHaveBeenCalledWith(
            '/event/OpenSF__Quantum_Job_Complete__e',
            -1,
            expect.any(Function)
        );
        expect(mockSubscribe).toHaveBeenCalledWith(
            '/event/OpenSF__Quantum_Job_Failed__e',
            -1,
            expect.any(Function)
        );
    });

    it('registers error handler on first call', () => {
        subscribeToQuantumEvents(jest.fn(), jest.fn());
        expect(mockOnError).toHaveBeenCalledTimes(1);
    });

    it('returns handle object', () => {
        const handle = subscribeToQuantumEvents(jest.fn(), jest.fn());
        expect(handle).toHaveProperty('complete');
        expect(handle).toHaveProperty('failed');
    });

    it('subscribes only to Complete when no onFailed provided', () => {
        subscribeToQuantumEvents(jest.fn());

        expect(mockSubscribe).toHaveBeenCalledTimes(1);
        expect(mockSubscribe).toHaveBeenCalledWith(
            '/event/OpenSF__Quantum_Job_Complete__e',
            -1,
            expect.any(Function)
        );
    });

    it('does not subscribe when both callbacks are null', () => {
        subscribeToQuantumEvents(null, null);
        expect(mockSubscribe).not.toHaveBeenCalled();
    });

    it('unsubscribes from both channels', async () => {
        const handle = { complete: { id: 'sub-1' }, failed: { id: 'sub-2' } };
        unsubscribeFromQuantumEvents(handle);

        expect(mockUnsubscribe).toHaveBeenCalledTimes(2);
        expect(mockUnsubscribe).toHaveBeenCalledWith({ id: 'sub-1' });
        expect(mockUnsubscribe).toHaveBeenCalledWith({ id: 'sub-2' });
        expect(handle.complete).toBeNull();
        expect(handle.failed).toBeNull();
    });

    it('handles null handle gracefully', () => {
        expect(() => unsubscribeFromQuantumEvents(null)).not.toThrow();
    });

    it('handles partial handle (only complete)', () => {
        const handle = { complete: { id: 'sub-1' }, failed: null };
        unsubscribeFromQuantumEvents(handle);

        expect(mockUnsubscribe).toHaveBeenCalledTimes(1);
        expect(mockUnsubscribe).toHaveBeenCalledWith({ id: 'sub-1' });
    });

    it('calls onComplete callback when message arrives', async () => {
        const onComplete = jest.fn();
        subscribeToQuantumEvents(onComplete, null);

        // Get the callback passed to subscribe
        const subscribeCallback = mockSubscribe.mock.calls[0][2];
        const mockMessage = { data: { payload: { jobId: 'j1' } } };
        subscribeCallback(mockMessage);

        expect(onComplete).toHaveBeenCalledWith(mockMessage);
    });

    it('calls onFailed callback when failure message arrives', async () => {
        const onFailed = jest.fn();
        subscribeToQuantumEvents(jest.fn(), onFailed);

        // Get the callback for the Failed channel (second call)
        const subscribeCallback = mockSubscribe.mock.calls[1][2];
        const mockMessage = {
            data: { payload: { jobId: 'j2', error: 'fail' } }
        };
        subscribeCallback(mockMessage);

        expect(onFailed).toHaveBeenCalledWith(mockMessage);
    });
});
