# AgentLayout Development Guidelines

## Testing

### Running Tests with Coverage

```bash
# Run all tests with code coverage enabled
swift test --enable-code-coverage

# Generate coverage report (after running tests)
xcrun llvm-cov report .build/arm64-apple-macosx/debug/AgentKitPackageTests.xctest/Contents/MacOS/AgentKitPackageTests \
  --instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  --ignore-filename-regex='.build|Tests'

# Export detailed coverage to HTML (optional)
xcrun llvm-cov show .build/arm64-apple-macosx/debug/AgentKitPackageTests.xctest/Contents/MacOS/AgentKitPackageTests \
  --instr-profile .build/arm64-apple-macosx/debug/codecov/default.profdata \
  --format=html \
  --output-dir=coverage-report \
  --ignore-filename-regex='.build|Tests'
```

### Coverage Target

- Target: **80%** line coverage
- Current: ~77% (some declarative UI/theme code is hard to test with unit tests)

### Test Structure

- **AgentTests**: Tests for Agent module (AgentClient, OpenAI types, parsing)
- **AgentLayoutTests**: Tests for UI components (MessageRow, JSONView, ModelPicker, etc.)

### Writing Tests

- Use Swift Testing framework (`@Test` macro)
- Use ViewInspector for SwiftUI view testing
- UI components should test structure exists, not visual appearance
- Mark test structs with `@MainActor` for SwiftUI views

## Code Style

- Prefer Swift Package Manager
- Use SwiftUI for all UI components
- Follow existing naming conventions
