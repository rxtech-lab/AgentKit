import Foundation
import Testing

@testable import Agent

// MARK: - CustomAgentModel Tests

@Suite("CustomAgentModel Tests")
struct CustomAgentModelTests {

    @Test func testCustomAgentModelInit() {
        let model = CustomAgentModel(id: "my-agent", name: "My Custom Agent")

        #expect(model.id == "my-agent")
        #expect(model.name == "My Custom Agent")
    }

    @Test func testCustomAgentModelHashable() {
        let model1 = CustomAgentModel(id: "agent-1", name: "Agent 1")
        let model2 = CustomAgentModel(id: "agent-2", name: "Agent 2")
        let model1Duplicate = CustomAgentModel(id: "agent-1", name: "Agent 1")

        var set: Set<CustomAgentModel> = []
        set.insert(model1)
        set.insert(model2)
        set.insert(model1Duplicate)

        #expect(set.count == 2)
    }

    @Test func testCustomAgentModelEquatable() {
        let model1 = CustomAgentModel(id: "agent-1", name: "Agent 1")
        let model2 = CustomAgentModel(id: "agent-1", name: "Agent 1")
        let model3 = CustomAgentModel(id: "agent-2", name: "Agent 2")

        #expect(model1 == model2)
        #expect(model1 != model3)
    }
}

// MARK: - Model.customAgent Tests

@Suite("Model CustomAgent Tests")
struct ModelCustomAgentTests {

    @Test func testModelCustomAgentCase() {
        let customAgentModel = CustomAgentModel(id: "my-agent", name: "My Agent")
        let model = Model.customAgent(customAgentModel)

        #expect(model.id == "my-agent")
        #expect(model.displayName == "My Agent")
    }

    @Test func testModelIsCustomAgentTrue() {
        let customAgentModel = CustomAgentModel(id: "my-agent", name: "My Agent")
        let model = Model.customAgent(customAgentModel)

        #expect(model.isCustomAgent == true)
    }

    @Test func testModelIsCustomAgentFalseForOpenAI() {
        let model = Model.openAI(OpenAICompatibleModel(id: "gpt-4"))

        #expect(model.isCustomAgent == false)
    }

    @Test func testModelIsCustomAgentFalseForOpenRouter() {
        let model = Model.openRouter(OpenAICompatibleModel(id: "claude-3"))

        #expect(model.isCustomAgent == false)
    }

    @Test func testModelIsCustomAgentFalseForCustomModel() {
        let model = Model.custom(CustomModel(id: "custom-model"))

        #expect(model.isCustomAgent == false)
    }

    @Test func testModelCustomAgentReasoningConfigNil() {
        let customAgentModel = CustomAgentModel(id: "my-agent", name: "My Agent")
        let model = Model.customAgent(customAgentModel)

        #expect(model.reasoningConfig == nil)
    }

    @Test func testModelCustomAgentHashable() {
        let agent1 = Model.customAgent(CustomAgentModel(id: "agent-1", name: "Agent 1"))
        let agent2 = Model.customAgent(CustomAgentModel(id: "agent-2", name: "Agent 2"))
        let agent1Duplicate = Model.customAgent(CustomAgentModel(id: "agent-1", name: "Agent 1"))

        var set: Set<Model> = []
        set.insert(agent1)
        set.insert(agent2)
        set.insert(agent1Duplicate)

        #expect(set.count == 2)
    }
}

// MARK: - Source.customAgent Tests

@Suite("Source CustomAgent Tests")
struct SourceCustomAgentTests {

    @Test func testSourceCustomAgentInit() {
        let customAgentModel = CustomAgentModel(id: "my-agent", name: "My Agent")
        let models = [Model.customAgent(customAgentModel)]
        let source = Source.customAgent(id: "custom-source", displayName: "Custom Agents", models: models)

        #expect(source.id == "custom-source")
        #expect(source.displayName == "Custom Agents")
        #expect(source.models.count == 1)
    }

    @Test func testSourceIsCustomAgentTrue() {
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [])

        #expect(source.isCustomAgent == true)
    }

    @Test func testSourceIsCustomAgentFalseForOpenAI() {
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [])

        #expect(source.isCustomAgent == false)
    }

    @Test func testSourceIsCustomAgentFalseForOpenRouter() {
        let source = Source.openRouter(client: OpenRouterClient(apiKey: "test"), models: [])

        #expect(source.isCustomAgent == false)
    }

    @Test func testSourceCustomAgentClientIsNil() {
        let source = Source.customAgent(id: "custom-source", displayName: "Custom", models: [])

        #expect(source.client == nil)
    }

    @Test func testSourceOpenAIClientIsNotNil() {
        let source = Source.openAI(client: OpenAIClient(apiKey: "test"), models: [])

        #expect(source.client != nil)
    }

    @Test func testSourceCustomAgentEquatable() {
        let source1 = Source.customAgent(id: "custom-1", displayName: "Custom 1", models: [])
        let source2 = Source.customAgent(id: "custom-1", displayName: "Custom 1", models: [])
        let source3 = Source.customAgent(id: "custom-2", displayName: "Custom 2", models: [])

        #expect(source1 == source2)
        #expect(source1 != source3)
    }

    @Test func testSourceCustomAgentWithMultipleModels() {
        let models: [Model] = [
            .customAgent(CustomAgentModel(id: "agent-1", name: "Agent 1")),
            .customAgent(CustomAgentModel(id: "agent-2", name: "Agent 2")),
            .customAgent(CustomAgentModel(id: "agent-3", name: "Agent 3"))
        ]
        let source = Source.customAgent(id: "multi-agent-source", displayName: "Multiple Agents", models: models)

        #expect(source.models.count == 3)
        #expect(source.models[0].displayName == "Agent 1")
        #expect(source.models[1].displayName == "Agent 2")
        #expect(source.models[2].displayName == "Agent 3")
    }
}
