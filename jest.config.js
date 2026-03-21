const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    testPathIgnorePatterns: ['/node_modules/', '<rootDir>/e2e/'],
    moduleNameMapper: {
        ...jestConfig.moduleNameMapper,
        '^lightning/empApi$':
            '<rootDir>/force-app/test/jest-mocks/lightning/empApi',
        '^lightning/platformShowToastEvent$':
            '<rootDir>/force-app/test/jest-mocks/lightning/platformShowToastEvent'
    },
    collectCoverageFrom: [
        '**/lwc/**/*.js',
        '!**/__tests__/**',
        '!**/jest-mocks/**'
    ],
    coverageThreshold: {
        global: {
            branches: 60,
            functions: 80,
            lines: 80,
            statements: 80
        }
    }
};
