//
//  TweakAccessorCodeGenerator.swift
//  Copyright © 2021 Just Eat Takeaway. All rights reserved.
//

import Foundation

class TweakAccessorCodeGenerator {
    
    private let featuresConst = "Features"
    private let variablesConst = "Variables"
    
    private let featureConstantsConst = "<FEATURE_CONSTANTS_CONST>"
    private let variableConstantsConst = "<VARIABLE_CONSTANTS_CONST>"
    private let classContentConst = "<CLASS_CONTENT>"
    private let tweakManagerConst = "<TWEAK_MANAGER_CONTENT>"
}

extension TweakAccessorCodeGenerator {
    
    func generateConstantsFileContent(tweaks: [Tweak],
                                      configuration: Configuration) -> String {
        let template = self.constantsTemplate(with: configuration.accessorName)
        let featureConstants = self.featureConstantsCodeBlock(with: tweaks)
        let variableConstants = self.variableConstantsCodeBlock(with: tweaks)
        
        let content = template
            .replacingOccurrences(of: featureConstantsConst, with: featureConstants)
            .replacingOccurrences(of: variableConstantsConst, with: variableConstants)
        return content
    }
    
    func generateAccessorFileContent(tweaksFilename: String,
                                     tweaks: [Tweak],
                                     configuration: Configuration) -> String {
        let template = self.accessorTemplate(with: configuration.accessorName)
        let tweakManager = self.tweakManagerCodeBlock(with: configuration)
        let classContent = self.classContent(with: tweaks)
        
        let content = template
            .replacingOccurrences(of: tweakManagerConst, with: tweakManager)
            .replacingOccurrences(of: classContentConst, with: classContent)
        return content
    }
    
    func constantsTemplate(with className: String) -> String {
        """
        //
        //  \(className)+Constants.swift
        //  Generated by TweakAccessorGenerator
        //
        
        import Foundation
        
        extension \(className) {
        
        \(featureConstantsConst)
        
        \(variableConstantsConst)
        }
        """
    }
    
    private func accessorTemplate(with className: String) -> String {
        """
        //
        //  \(className).swift
        //  Generated by TweakAccessorGenerator
        //
        
        import Foundation
        import JustTweak
        
        class \(className) {

        \(tweakManagerConst)
        
        \(classContentConst)
        }
        """
    }
    
    private func featureConstantsCodeBlock(with tweaks: [Tweak]) -> String {
        var features = Set<FeatureKey>()
        for tweak in tweaks {
            features.insert(tweak.feature)
        }
        let content: [String] = features.map {
            """
                    static let \($0.camelCased()) = "\($0)"
            """
        }
        return """
            struct \(featuresConst) {
        \(content.sorted().joined(separator: "\n"))
            }
        """
    }
    
    private func variableConstantsCodeBlock(with tweaks: [Tweak]) -> String {
        var variables = Set<VariableKey>()
        for tweak in tweaks {
            variables.insert(tweak.variable)
        }
        let content: [String] = variables.map {
            """
                    static let \($0.camelCased()) = "\($0)"
            """
        }
        return """
            struct \(variablesConst) {
        \(content.sorted().joined(separator: "\n"))
            }
        """
    }
    
    private func tweakManagerCodeBlock(with configuration: Configuration) -> String {
        let tweakProvidersCodeBlock = self.tweakProvidersCodeBlock(with: configuration)
        
        return """
            static let tweakManager: TweakManager = {
        \(tweakProvidersCodeBlock)
                let tweakManager = TweakManager(tweakProviders: tweakProviders)
                tweakManager.useCache = \(configuration.shouldCacheTweaks)
                return tweakManager
            }()
                
            private var tweakManager: TweakManager {
                return Self.tweakManager
            }
        """
    }
    
    private func tweakProvidersCodeBlock(with configuration: Configuration) -> String {
        let grouping = Dictionary(grouping: configuration.tweakProviders) { $0.type }
        
        var tweakProvidersString: [String] = [
            """
                    var tweakProviders: [TweakProvider] = []\n
            """
        ]
        
        var currentIndexByConf: [String: Int] = grouping.mapValues{ _ in 0 }
        
        for tweakProvider in configuration.tweakProviders {
            let value = grouping[tweakProvider.type]!
            let index = currentIndexByConf[tweakProvider.type]!
            let tweakProvider = value[index]
            let tweakProviderName = "\(tweakProvider.type.lowercasedFirstChar())_\(index+1)"
            var generatedString: [String] = []
            let macros = tweakProvider.macros?.joined(separator: " || ")
            
            let jsonFileURL = "jsonFileURL_\(index+1)"
            let headerComment = """
                        // \(tweakProvider.type)
                """
            generatedString.append(headerComment)
                
            if macros != nil {
                let macroStarting = """
                        #if \(macros!)
                """
                generatedString.append(macroStarting)
            }
            
            switch tweakProvider.type {
            case "EphemeralTweakProvider":
                let tweakProviderAllocation =
                    """
                            let \(tweakProviderName) = NSMutableDictionary()
                            tweakProviders.append(\(tweakProviderName))
                    """
                generatedString.append(tweakProviderAllocation)

            case "UserDefaultsTweakProvider":
                assert(tweakProvider.parameter != nil, "Missing value 'parameter' for TweakProvider '\(tweakProvider)'")
                let tweakProviderAllocation =
                    """
                            let \(tweakProviderName) = \(tweakProvider.type)(userDefaults: \(tweakProvider.parameter!))
                            tweakProviders.append(\(tweakProviderName))
                    """
                generatedString.append(tweakProviderAllocation)
                
            case "LocalTweakProvider":
                assert(tweakProvider.parameter != nil, "Missing value 'parameter' for TweakProvider '\(tweakProvider)'")
                let tweakProviderAllocation =
                    """
                            let \(jsonFileURL) = Bundle.main.url(forResource: \"\(tweakProvider.parameter!)\", withExtension: "json")!
                            let \(tweakProviderName) = \(tweakProvider.type)(jsonURL: \(jsonFileURL))
                            tweakProviders.append(\(tweakProviderName))
                    """
                generatedString.append(tweakProviderAllocation)
                
            case "CustomTweakProvider":
                assert(tweakProvider.parameter != nil, "Missing value 'parameter' for TweakProvider '\(tweakProvider)'")
                let tweakProviderAllocation =
                    """
                            \(tweakProvider.parameter!)
                    """
                generatedString.append(tweakProviderAllocation)
                
            default:
                assertionFailure("Unsupported TweakProvider \(tweakProvider)")
                break
            }
            
            if macros != nil {
                let macroClosing = """
                        #endif
                """
                generatedString.append(macroClosing)
            }
            generatedString.append("")
            
            tweakProvidersString.append(contentsOf: generatedString)
            currentIndexByConf[tweakProvider.type] = currentIndexByConf[tweakProvider.type]! + 1
        }
        
        return tweakProvidersString.joined(separator: "\n")
    }
    
    private func classContent(with tweaks: [Tweak]) -> String {
        var content: Set<String> = []
        tweaks.forEach {
            content.insert(tweakProperty(for: $0))
        }
        return content.sorted().joined(separator: "\n\n")
    }
    
    private func tweakProperty(for tweak: Tweak) -> String {
        let propertyName = tweak.propertyName ?? tweak.variable.camelCased()
        return """
            @TweakProperty(feature: \(featuresConst).\(tweak.feature.camelCased()),
                           variable: \(variablesConst).\(tweak.variable.camelCased()),
                           tweakManager: tweakManager)
            var \(propertyName): \(tweak.valueType)
        """
    }
}
