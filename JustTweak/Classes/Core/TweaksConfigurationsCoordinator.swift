//
//  TweaksConfigurationsCoordinator.swift
//  Copyright (c) 2016 Just Eat Holding Ltd. All rights reserved.
//

import Foundation

@objcMembers
@objc final public class TweaksConfigurationsCoordinator: NSObject {
    
    private struct TweakCachedValue: Hashable {
        let tweak: Tweak
        let source: String
        
        var hashValue: Int {
            return tweak.identifier.hashValue
        }
        
        static func ==(lhs: TweakCachedValue, rhs: TweakCachedValue) -> Bool {
            return lhs.tweak.identifier == rhs.tweak.identifier
        }
    }
    
    public var logClosure: TweaksLogClosure = {(message, logLevel) in  print(message) } {
        didSet {
            configurations.forEach {
                $0.logClosure = logClosure
            }
        }
    }
    
    private let configurations: [TweaksConfiguration]
    private var tweaksCache = [String : [String : TweakCachedValue]]()
    private var observersMap = [NSObject : NSObjectProtocol]()
    
    public init?(configurations: [TweaksConfiguration]) {
        guard configurations.count > 0 else { return nil }
        self.configurations = configurations.sorted(by: { $0.priority.rawValue > $1.priority.rawValue })
        logClosure("Configurations lookup order => \(self.configurations) ", .verbose)
        super.init()
        self.configurations.forEach {
            $0.logClosure = logClosure
        }
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(resetCache), name: TweaksConfigurationDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public func tweakWith(feature: String, variable: String) -> Tweak? {
        if let cachedVariables = tweaksCache[feature], let cachedVariable = cachedVariables[variable] {
            logClosure("Tweak '\(cachedVariable.tweak)' found in cache.)", .verbose)
            return cachedVariable.tweak
        }
        
        var result: Tweak? = nil
        var valueSource: String? = nil
        for (_, configuration) in configurations.enumerated() {
            if let tweak = configuration.tweakWith(feature: feature, variable: variable) {
                logClosure("Tweak '\(tweak)' found in configuration \(configuration))", .verbose)
                valueSource = valueSource ?? "\(type(of: configuration))"
                result = Tweak(identifier: variable,
                               title: result?.title ?! tweak.title,
                               group: result?.group ?! tweak.group,
                               value: result?.value ?! tweak.value,
                               canBeDisplayed: result?.canBeDisplayed ||| tweak.canBeDisplayed) // always displayable if any configuration allows it
            }
            else {
                logClosure("Tweak with identifier '\(variable)' NOT found in configuration \(configuration))", .verbose)
            }
        }
        if let result = result, let valueSource = valueSource {
            logClosure("Tweak with feature '\(feature)' and variable '\(variable)' resolved. Using '\(result)'.", .debug)
            let cachedTweak = TweakCachedValue(tweak: result, source: valueSource)
            if let _ = tweaksCache[feature] {
                tweaksCache[feature]?[variable] = cachedTweak
            } else {
                tweaksCache[feature] = [variable : cachedTweak]
            }
        }
        else {
            logClosure("No Tweak found for identifier '\(variable)'", .error)
        }
        return result
    }
    
    public func valueForTweakWith(feature: String, variable: String) -> TweakValue? {
        return tweakWith(feature: feature, variable: variable)?.value
    }
    
    public func topCustomizableConfiguration() -> MutableTweaksConfiguration? {
        for configuration in configurations {
            if let configuration = configuration as? MutableTweaksConfiguration {
                return configuration
            }
        }
        return nil
    }
    
    public func displayableTweaks() -> [Tweak] {
        var allTweaks = [Tweak]()
        if let allTweakIdentifiers = topCustomizableConfiguration()?.allTweakIdentifiers {
            for identifier in allTweakIdentifiers {
                if let tweak = tweakWith(feature: "", variable: identifier), tweak.canBeDisplayed {
                    allTweaks.append(tweak)
                }
            }
        }
        return allTweaks
    }
    
    public func registerForConfigurationsUpdates(_ object: NSObject, closure: @escaping () -> Void) {
        deregisterFromConfigurationsUpdates(object)
        let queue = OperationQueue.main
        let name = TweaksConfigurationDidChangeNotification
        let notificationsCenter = NotificationCenter.default
        let observer = notificationsCenter.addObserver(forName: name, object: nil, queue: queue) { (_) in
            closure()
        }
        observersMap[object] = observer
    }
    
    public func deregisterFromConfigurationsUpdates(_ object: NSObject) {
        guard let observer = observersMap[object] else { return }
        NotificationCenter.default.removeObserver(observer)
        observersMap.removeValue(forKey: object)
    }
    
    @objc public func resetCache() {
        tweaksCache = [String : [String : TweakCachedValue]]()
    }
    
}
