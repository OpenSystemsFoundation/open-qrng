/**
 * Mock for lightning/empApi used in LWC Jest tests.
 * Simulates Platform Event subscription lifecycle.
 */
export const subscribe = jest
    .fn()
    .mockResolvedValue({ id: 'mock-subscription' });
export const unsubscribe = jest.fn().mockResolvedValue(true);
export const onError = jest.fn();
export const setDebugFlag = jest.fn();
export const isEmpEnabled = jest.fn().mockResolvedValue(true);
