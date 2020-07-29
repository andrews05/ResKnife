import Cocoa

public extension FourCharCode {
    var stringValue: String {
        return UTCreateStringForOSType(self).takeRetainedValue() as String
    }
    init(_ string: String) {
        self = UTGetOSTypeFromString(string as CFString)
    }
}

@objc public protocol ResKnifePlugin {
    @objc var resource: Resource { get }
    @objc init(resource: Resource)
    
    @objc optional func saveResource(_ sender: Any)
    @objc optional func revertResource(_ sender: Any)
    
    /// You can return here the filename extension for your resource type. By default the host application substitutes the resource type if you do not implement this.
    @objc optional static func filenameExtension(for resourceType: String) -> String
    
    /// Implement this if the plugin needs to control the data that gets written to disk on export. By default the host application writes the raw resource data.
    /// The idea is that this export function is non-lossy, i.e. only override this if there is a format that is a 100% equivalent to your data.
    @objc optional static func export(_ resource: Resource, to url: URL)
    
    /// Return the icon to be used throughout the UI for any given resource type.
    @objc optional static func icon(for resourceType: String) -> NSImage?

    /// Return an NSImage representing the resource for use in grid view
    @objc optional static func image(for resource: Resource) -> NSImage?
}

@objc public protocol ResKnifeTemplatePlugin: ResKnifePlugin {
    @objc init(resource: Resource, template: Resource)
}

@objc public protocol ResKnifePluginManager {
    @objc func open(resource: Resource, using editor: ResKnifePlugin.Type?, template: Resource?)
//    @objc static func allResources(ofType: String, document: NSDocument?) -> [Resource]
//    @objc static func findResource(ofType: String, id: Int, document: NSDocument?) -> Resource?
//    @objc static func findResource(ofType: String, name: String, document: NSDocument?) -> Resource?
    @objc func allResources(ofType: String, currentDocumentOnly: Bool) -> [Resource]
    @objc func findResource(ofType: String, id: Int, currentDocumentOnly: Bool) -> Resource?
    @objc func findResource(ofType: String, name: String, currentDocumentOnly: Bool) -> Resource?
}