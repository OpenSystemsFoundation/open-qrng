const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    moduleNameMapper: {
        ...jestConfig.moduleNameMapper,
        '^lightning/empApi$':
            '<rootDir>/force-app/test/jest-mocks/lightning/empApi',
        '^lightning/platformShowToastEvent$':
            '<rootDir>/force-app/test/jest-mocks/lightning/platformShowToastEvent'
    },
    coverageThreshold: {
        global: {
            branches: 45,
            functions: 60,
            lines: 70,
            statements: 70
        }
    }
};
