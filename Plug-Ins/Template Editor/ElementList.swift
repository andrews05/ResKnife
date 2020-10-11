import Cocoa
import RKSupport

enum TemplateError: Error {
    case corrupt
    case unknownElement(type: String)
}

class ElementList: NSObject, NSCopying {
    let parentList: ElementList?
    @objc private(set) weak var controller: TemplateWindowController!
    private var elements: [Element] = []
    private var visibleElements: [Element] = []
    private var currentIndex = 0
    private var configured = false
    @objc var count: Int {
        return visibleElements.count
    }
    
    init(from template: Data, controller: TemplateWindowController) throws {
        parentList = nil
        self.controller = controller
        super.init()
        let reader = BinaryDataReader(template)
        while reader.position < reader.data.endIndex {
            let element = try self.readElement(from: reader)
            elements.append(element)
        }
    }
    
    private init(parent: ElementList?, controller: TemplateWindowController) {
        parentList = parent
        self.controller = controller
        super.init()
    }
    
    func copy(with zone: NSZone? = nil) -> Any {
        let list = ElementList(parent: parentList, controller: controller)
        list.elements = elements.map({ $0.copy() as! Element })
        list.configureElements()
        return list
    }
    
    @objc func configureElements() {
        guard !configured else {
            return
        }
        while currentIndex < elements.count {
            let element = elements[currentIndex]
            element.parentList = self
            if element.visible {
                visibleElements.append(element)
            }
            element.configure()
            currentIndex += 1
        }
        configured = true
    }
    
    func readResource(data: Data) {
        self.readData(from: ResourceStream(data: NSMutableData(data: data)))
    }
    
    func getResourceData() -> Data {
        let size = self.sizeOnDisk()
        let data = NSMutableData(length: Int(size))!
        let stream = ResourceStream(data: data)!
        self.writeData(to: stream)
        return Data(data)
    }
    
    // MARK: -
    
    @objc func element(at index: Int) -> Element {
        return visibleElements[index]
    }

    // Insert a new element at the current position
    @objc func insert(_ element: Element) {
        element.parentList = self
        if !configured {
            // Insert after current element during configure (e.g. fixed count list, keyed section)
            currentIndex += 1
            elements.insert(element, at: currentIndex)
            if element.visible {
                visibleElements.append(element)
            }
        } else {
            // Insert before current element during read (e.g. other lists)
            elements.insert(element, at: currentIndex)
            currentIndex += 1
            if element.visible {
                let visIndex = visibleElements.firstIndex(of: elements[currentIndex])!
                visibleElements.insert(element, at: visIndex)
            }
        }
    }
    
    // Insert a new element before/after a given element
    @objc func insert(_ element: Element, before: Element) {
        elements.insert(element, at: elements.firstIndex(of: before)!)
        element.parentList = self
        if element.visible {
            visibleElements.insert(element, at: visibleElements.firstIndex(of: before)!)
        }
    }
    
    @objc func insert(_ element: Element, after: Element) {
        elements.insert(element, at: elements.firstIndex(of: after)! + 1)
        element.parentList = self
        if element.visible {
            visibleElements.insert(element, at: visibleElements.firstIndex(of: element)! + 1)
        }
    }
    
    @objc func remove(_ element: Element) {
        elements.removeAll(where: { $0 == element })
        visibleElements.removeAll(where: { $0 == element })
    }
    
    // MARK: -
    
    // The following methods may be used by elements while reading their sub elements
    
    // Peek at an element in the list without removing it
    @objc func peek(_ n: Int) -> Element? {
        let i = currentIndex + n
        return i < elements.endIndex ? elements[i] : nil
    }
    
    // Pop the next element out of the list
    @objc func pop() -> Element? {
        let i = currentIndex + 1
        if i >= elements.endIndex {
            return nil
        }
        let element = elements[i]
        elements.remove(at: i)
        return element
    }
    
    // Search for an element of a given type following the current one
    @objc func next(ofType type: String) -> Element? {
        return elements[(currentIndex+1)...].first(where: { $0.type == type })
    }
    
    // Search for an element of a given type preceding the current one, travsersing up the hierarchy if necessary
    @objc func previous(ofType type: String) -> Element? {
        if let element = elements[0..<currentIndex].last(where: { $0.type == type }) {
            return element
        }
        if let list = parentList {
            return list.previous(ofType: type)
        }
        return nil
    }
    
    @objc func next(withLabel label: String) -> Element? {
        return elements[(currentIndex+1)...].first(where: { $0.displayLabel() == label })
    }
    
    // Create a new ElementList by extracting all elements following the current one up until a given type
    @objc func subList(for startElement: Element) -> ElementList {
        let list = ElementList(parent: self, controller: controller)
        var nesting = 0
        while true {
            guard let element = self.pop() else {
                print("Closing '\(startElement.endType!)' element not found for opening '\(startElement.type!)'.")
                break
            }
            if element.endType == startElement.endType {
                nesting += 1
            } else if element.type == startElement.endType {
                if nesting == 0 {
                    break
                }
                nesting -= 1
            }
            list.elements.append(element)
        }
        return list
    }
    
    // MARK: -
    
    @objc func readData(from stream: ResourceStream) {
        currentIndex = 0;
        // Don't use fast enumeration here as the list may be modified while reading
        while currentIndex < elements.count {
            if stream.bytesToGo == 0 {
                return
            }
            elements[currentIndex].readData(from: stream)
            currentIndex += 1
        }
    }
    
    @objc func sizeOnDisk() -> UInt32 {
        var size: UInt32 = 0
        for element in elements {
            element.size(onDisk: &size)
        }
        return size
    }
    
    @objc func writeData(to stream: ResourceStream) {
        for element in elements {
            element.writeData(to: stream)
        }
    }
    
    // MARK: -
    
    func readElement(from reader: BinaryDataReader) throws -> Element {
        let label = try reader.readPString(encoding: .macOSRoman)
        let typeCode: FourCharCode = try reader.read()
        let type = typeCode.stringValue
        
        var elType = Self.fieldRegistry[type]
        // check for Xnnn type - currently using resorcerer's nmm restriction to reserve all alpha types (e.g. FACE) for potential future use
        if elType == nil && type.range(of: "[A-Z](?!000)[0-9][0-9A-F]{2}", options: .regularExpression) != nil {
            elType = Self.fieldRegistry[String(type.prefix(1))]
        }
        // check for XXnn type
        if elType == nil && type.range(of: "[A-Z]{2}(?!00)[0-9]{2}", options: .regularExpression) != nil {
            elType = Self.fieldRegistry[String(type.prefix(2))]
        }
        if let elType = elType, let element = elType.init(forType: type, withLabel: label) {
            return element
        }
        throw TemplateError.unknownElement(type: type)
    }
    
    static let fieldRegistry: [String: Element.Type] = [
        "DBYT": ElementDBYT.self,   // signed ints
        "DWRD": ElementDWRD.self,
        "DLNG": ElementDLNG.self,
        "DLLG": ElementDLLG.self,   // (ResKnife)
        "UBYT": ElementUBYT.self,   // unsigned ints
        "UWRD": ElementUWRD.self,
        "ULNG": ElementULNG.self,
        "ULLG": ElementULLG.self,   // (ResKnife)
        "HBYT": ElementHBYT.self,   // hex byte/word/long
        "HWRD": ElementHWRD.self,
        "HLNG": ElementHLNG.self,
        "HLLG": ElementHLLG.self,   // (ResKnife)
        
        // multiple fields
        "RECT": ElementRECT.self,   // QuickDraw rect
        "PNT ": ElementPNT.self,    // QuickDraw point
        
        // align & fill
        "AWRD": ElementAWRD.self,   // alignment ints
        "ALNG": ElementAWRD.self,
        "AL08": ElementAWRD.self,
        "AL16": ElementAWRD.self,
        "FBYT": ElementFBYT.self,   // filler ints
        "FWRD": ElementFBYT.self,
        "FLNG": ElementFBYT.self,
        "FLLG": ElementFBYT.self,
        "F"   : ElementFBYT.self,   // Fnnn
        
        // fractions
        "REAL": ElementREAL.self,   // single precision float
        "DOUB": ElementDOUB.self,   // double precision float
        "FIXD": ElementFIXD.self,   // 16.16 fixed fraction
        "FRAC": ElementFRAC.self,   // 2.30 fixed fraction
        
        // strings
        "PSTR": ElementPSTR.self,
        "BSTR": ElementPSTR.self,
        "WSTR": ElementPSTR.self,
        "LSTR": ElementPSTR.self,
        "OSTR": ElementPSTR.self,
        "ESTR": ElementPSTR.self,
        "CSTR": ElementPSTR.self,
        "OCST": ElementPSTR.self,
        "ECST": ElementPSTR.self,
        "P"   : ElementPSTR.self,   // Pnnn
        "C"   : ElementPSTR.self,   // Cnnn
        "CHAR": ElementCHAR.self,
        "TNAM": ElementTNAM.self,
        
        // bits
        "BOOL": ElementBOOL.self,   // true = 256; false = 0
        "BFLG": ElementBFLG.self,   // binary flag the size of a byte/word/long
        "WFLG": ElementWFLG.self,
        "LFLG": ElementLFLG.self,
        "BBIT": ElementBBIT.self,   // bit within a byte
        "BB"  : ElementBBIT.self,   // BBnn bit field
        "BF"  : ElementBBIT.self,   // BFnn fill bits (ResKnife)
        "WBIT": ElementWBIT.self,
        "WB"  : ElementWBIT.self,   // WBnn
        "WF"  : ElementWBIT.self,   // WFnn (ResKnife)
        "LBIT": ElementLBIT.self,
        "LB"  : ElementLBIT.self,   // LBnn
        "LF"  : ElementLBIT.self,   // LFnn (ResKnife)
        "BORV": ElementBORV.self,   // byte/word/long OR-value (Rezilla)
        "WORV": ElementWORV.self,
        "LORV": ElementLORV.self,
        
        // hex dumps
        "BHEX": ElementHEXD.self,
        "WHEX": ElementHEXD.self,
        "LHEX": ElementHEXD.self,
        "BSEX": ElementHEXD.self,
        "WSEX": ElementHEXD.self,
        "LSEX": ElementHEXD.self,
        "HEXD": ElementHEXD.self,
        "H"   : ElementHEXD.self,   // Hnnn
        
        // list counters
        "OCNT": ElementOCNT.self,
        "ZCNT": ElementOCNT.self,
        "BCNT": ElementOCNT.self,
        "BZCT": ElementOCNT.self,   // (ResKnife)
        "WCNT": ElementOCNT.self,
        "WZCT": ElementOCNT.self,   // (ResKnife)
        "LCNT": ElementOCNT.self,
        "LZCT": ElementOCNT.self,
        "FCNT": ElementFCNT.self,   // fixed count with count in label (why didn't they choose Lnnn?)
        // list begin/end
        "LSTB": ElementLSTB.self,
        "LSTZ": ElementLSTB.self,
        "LSTC": ElementLSTB.self,
        "LSTE": Element.self,
        
        // option lists
        "CASE": ElementCASE.self,   // single option for preceding element
        "CASR": ElementCASR.self,   // option range for preceding element (ResKnife)
        "RSID": ElementRSID.self,   // resouce id (signed word) - type and offset in label
        
        // key selection
        "KBYT": ElementDBYT.self,   // signed keys
        "KWRD": ElementDWRD.self,
        "KLNG": ElementDLNG.self,
        "KLLG": ElementDLLG.self,   // (ResKnife)
        "KUBT": ElementUBYT.self,   // unsigned keys
        "KUWD": ElementUWRD.self,
        "KULG": ElementULNG.self,
        "KULL": ElementULLG.self,   // (ResKnife)
        "KHBT": ElementHBYT.self,   // hex keys
        "KHWD": ElementHWRD.self,
        "KHLG": ElementHLNG.self,
        "KHLL": ElementHLLG.self,   // (ResKnife)
        "KCHR": ElementCHAR.self,   // string keys
        "KTYP": ElementTNAM.self,
        "KRID": ElementKRID.self,   // key on ID of the resource
        // keyed section begin/end
        "KEYB": ElementKEYB.self,
        "KEYE": Element.self,
        
        // dates
        "DATE": ElementDATE.self,   // 4-byte date (seconds since 1 Jan 1904)
        "MDAT": ElementDATE.self,
        
        // colours
        "COLR": ElementCOLR.self,   // 6-byte QuickDraw colour
        "WCOL": ElementCOLR.self,   // 2-byte (15-bit) colour (Rezilla)
        "LCOL": ElementCOLR.self,   // 4-byte (24-bit) colour (Rezilla)
        
        // layout
        "DVDR": ElementDVDR.self,   // divider
        "PACK": ElementPACK.self,   // pack other elements together (ResKnife)
        
        // and some faked ones just to increase compatibility (these are marked 'x' in the docs)
        "SFRC": ElementUWRD.self,   // 0.16 fixed fraction
        "FXYZ": ElementUWRD.self,   // 1.15 fixed fraction
        "FWID": ElementUWRD.self,   // 4.12 fixed fraction
        "LLDT": ElementULLG.self,   // 8-byte date (seconds since 1 Jan 1904) (ResKnife)
        "STYL": ElementDBYT.self,   // QuickDraw font style (ResKnife)
        "SCPC": ElementDWRD.self,   // MacOS script code (ScriptCode)
        "LNGC": ElementDWRD.self,   // MacOS language code (LangCode)
        "RGNC": ElementDWRD.self,   // MacOS region code (RegionCode)
    ]
}