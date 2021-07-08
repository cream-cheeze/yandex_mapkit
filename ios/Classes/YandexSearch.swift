import CoreLocation
import Flutter
import UIKit
import YandexMapsMobile

public class YandexSearch: NSObject, FlutterPlugin {
  
  private let methodChannel: FlutterMethodChannel!
  private let searchManager: YMKSearchManager!
  private var suggestSessionsById: [Int:YMKSearchSuggestSession] = [:]
  
  private var searchSession: YMKSearchSession?
  

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "yandex_mapkit/yandex_search",
      binaryMessenger: registrar.messenger()
    )
    let plugin = YandexSearch(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  public required init(channel: FlutterMethodChannel) {
    self.methodChannel = channel
    self.searchManager = YMKSearch.sharedInstance().createSearchManager(with: .combined)
    super.init()

    self.methodChannel.setMethodCallHandler(self.handle)
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSuggestions":
      getSuggestions(call)
      result(nil)
    case "cancelSuggestSession":
      cancelSuggestSession(call)
      result(nil)
    case "searchByText":
      searchByText(call)
      result(nil)
    case "cancelSearchSession":
      cancelSearchSession(call)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func cancelSuggestSession(_ call: FlutterMethodCall) {
    let params = call.arguments as! [String: Any]
    let listenerId = (params["listenerId"] as! NSNumber).intValue

    self.suggestSessionsById.removeValue(forKey: listenerId)
  }

  public func getSuggestions(_ call: FlutterMethodCall) {
    let params = call.arguments as! [String: Any]
    let listenerId = (params["listenerId"] as! NSNumber).intValue
    let formattedAddress = params["formattedAddress"] as! String
    let boundingBox = YMKBoundingBox.init(
      southWest: YMKPoint.init(
        latitude: (params["southWestLatitude"] as! NSNumber).doubleValue,
        longitude: (params["southWestLongitude"] as! NSNumber).doubleValue
      ),
      northEast: YMKPoint.init(
        latitude: (params["northEastLatitude"] as! NSNumber).doubleValue,
        longitude: (params["northEastLongitude"] as! NSNumber).doubleValue
      )
    )
    let suggestSession = self.searchManager!.createSuggestSession()
    let suggestType = YMKSuggestType.init(rawValue: (params["suggestType"] as! NSNumber).uintValue)
    let suggestOptions = YMKSuggestOptions.init(
      suggestTypes: suggestType,
      userPosition: nil,
      suggestWords: (params["suggestWords"] as! NSNumber).boolValue
    )

    suggestSession.suggest(
      withText: formattedAddress,
      window: boundingBox,
      suggestOptions: suggestOptions,
      responseHandler: buildResponseHandler(listenerId: listenerId)
    )
    self.suggestSessionsById[listenerId] = suggestSession;
  }

  private func buildResponseHandler(listenerId: Int) -> ([YMKSuggestItem]?, Error?) -> Void {
    return { (searchResponse: [YMKSuggestItem]?, error: Error?) -> Void in
      if searchResponse != nil {
        let suggestItems = searchResponse!.map({ (suggestItem) -> [String : Any] in
          var dict = [String : Any]()

          dict["title"] = suggestItem.title.text
          dict["subtitle"] = suggestItem.subtitle?.text
          dict["displayText"] = suggestItem.displayText
          dict["searchText"] = suggestItem.searchText
          dict["type"] = suggestItem.type.rawValue
          dict["tags"] = suggestItem.tags

          return dict
        })
        let arguments: [String:Any?] = [
          "listenerId": listenerId,
          "response": suggestItems
        ]
        self.methodChannel.invokeMethod("onSuggestListenerResponse", arguments: arguments)

        return
      }

      if error != nil {
        let arguments: [String:Any?] = [
          "listenerId": listenerId
        ]
        self.methodChannel.invokeMethod("onSuggestListenerError", arguments: arguments)

        return
      }
    }
  }
  
  public func searchByText(_ call: FlutterMethodCall) {
    
    let params = call.arguments as! [String: Any]
    
    let searchText = params["searchText"] as! String
    
    let searchTypeParam           = (params["searchType"] as! NSNumber).uintValue
    let resultPageSizeParam       = params["resultPageSize"] as? NSNumber
    let snippetsParam             = params["snippets"] as! [NSNumber]
    let experimentalSnippetsParam = params["experimentalSnippets"] as! [String]
    let userPositionParam         = params["userPosition"] as? [String:Any]
    
    let searchType = YMKSearchType.init(rawValue: searchTypeParam)
    
    let snippet = YMKSearchSnippet(
      rawValue: snippetsParam
        .map({ val in
          return val.uintValue
        })
        .reduce(0, |)
    )
    
    let userPosition = userPositionParam != nil
      ? YMKPoint.init(
          latitude: (userPositionParam!["latitude"] as! NSNumber).doubleValue,
          longitude: (userPositionParam!["longitude"] as! NSNumber).doubleValue
        )
      : nil
      
    let origin                    = params["origin"] as? String
    let directPageId              = params["directPageId"] as? String
    let appleCtx                  = params["appleCtx"] as? String
    let geometry                  = (params["geometry"] as! NSNumber).boolValue
    let advertPageId              = params["advertPageId"] as? String
    let suggestWords              = (params["suggestWords"] as! NSNumber).boolValue
    let disableSpellingCorrection = (params["disableSpellingCorrection"] as! NSNumber).boolValue
    
    let searchOptions = YMKSearchOptions.init(
      searchTypes: searchType,
      resultPageSize: resultPageSizeParam,
      snippets: snippet,
      experimentalSnippets: experimentalSnippetsParam,
      userPosition: userPosition,
      origin: origin,
      directPageId: directPageId,
      appleCtx: appleCtx,
      geometry: geometry,
      advertPageId: advertPageId,
      suggestWords: suggestWords,
      disableSpellingCorrection: disableSpellingCorrection
    )
    
    let responseHandler = {(searchResponse: YMKSearchResponse?, error: Error?) -> Void in
      if let response = searchResponse {
          self.onSearchResponse(response)
      } else {
          self.onSearchError(error!)
      }
    }
  
    searchSession = searchManager.submit(
      withText: searchText,
      geometry: YMKGeometry(point: YMKPoint(latitude: 55.716216, longitude: 37.470412)),
      searchOptions: searchOptions,
      responseHandler: responseHandler)
  }
  
  private func onSearchResponse(_ res: YMKSearchResponse) {
    
    var data = [String : Any]()
      
    data["found"] = res.metadata.found
    
    var dataItems = [[String : Any]]()
    
    for searchItem in res.collection.children {
      
      guard let obj = searchItem.obj else {
        continue
      }
      
      guard let toponymMeta = obj.metadataContainer.getItemOf(YMKSearchToponymObjectMetadata.self) as? YMKSearchToponymObjectMetadata else {
        continue
      }
      
      var dataItem = [String : Any]()
      
      dataItem["name"] = obj.name
      
      var toponymMetadata = [String : Any]()
      
      toponymMetadata["latitude"]  = toponymMeta.balloonPoint.latitude
      toponymMetadata["longitude"] = toponymMeta.balloonPoint.longitude

      toponymMetadata["formattedAddress"] = toponymMeta.address.formattedAddress

      var addressComponents = [Int : String]()
      
      toponymMeta.address.components.forEach {
        
        var flutterKind: Int = 0
        
        let value = $0.name

        $0.kinds.forEach {
          
          let kind = YMKSearchComponentKind(rawValue: UInt(truncating: $0))

          // Map kind to enum value in flutter
          switch kind {
          case .none, .some(.unknown):
            flutterKind = 0
          case .country:
            flutterKind = 1
          case .some(.region):
            flutterKind = 2
          case .some(.province):
            flutterKind = 3
          case .some(.area):
            flutterKind = 4
          case .some(.locality):
            flutterKind = 5
          case .some(.district):
            flutterKind = 6
          case .some(.street):
            flutterKind = 7
          case .some(.house):
            flutterKind = 8
          case .some(.entrance):
            flutterKind = 9
          case .some(.route):
            flutterKind = 10
          case .some(.station):
            flutterKind = 11
          case .some(.metroStation):
            flutterKind = 12
          case .some(.railwayStation):
            flutterKind = 13
          case .some(.vegetation):
            flutterKind = 14
          case .some(.hydro):
            flutterKind = 15
          case .some(.airport):
            flutterKind = 16
          case .some(.other):
            flutterKind = 17
          }
          
          addressComponents[flutterKind] = value
        }
      }
      
      toponymMetadata["addressComponents"] = addressComponents
      
      dataItem["toponymMetadata"] = toponymMetadata
      
      dataItems.append(dataItem)
    }
    
    data["items"] = dataItems
    
    let arguments: [String:Any?] = [
      "response": data
    ]
    
    self.methodChannel.invokeMethod("onSearchListenerResponse", arguments: arguments)

    return
  }
  
  private func onSearchError(_ error: Error) {
    
    let searchError = (error as NSError).userInfo[YRTUnderlyingErrorKey] as! YRTError
    
    var errorMessage = "Unknown error"
    
    if searchError.isKind(of: YRTNetworkError.self) {
        errorMessage = "Network error"
    } else if searchError.isKind(of: YRTRemoteError.self) {
        errorMessage = "Remote server error"
    }
    
    let arguments: [String:Any?] = [
      "error": errorMessage,
    ]
    
    self.methodChannel.invokeMethod("onSearchListenerError", arguments: arguments)

    return
  }
  
  public func cancelSearchSession(_ call: FlutterMethodCall) {
    
    searchSession?.cancel()

    searchSession = nil
  }
}
