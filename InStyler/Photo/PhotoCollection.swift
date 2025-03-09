//
//  PhotoCollection.swift
//  InStyler
//
//  Created by Denis Dzyuba on 5/3/2025.
//
import Photos

class PhotoCollection: NSObject, ObservableObject, @unchecked Sendable {
    
    @Published var photoAssets: PhotoAssetCollection = PhotoAssetCollection(PHFetchResult<PHAsset>())
    
    var identifier: String? {
        assetCollection?.localIdentifier
    }
    
    var albumName: String?
    
    var smartAlbumType: PHAssetCollectionSubtype?
    
    let cache = CachedImageManager()
    
    private var assetCollection: PHAssetCollection?
    
    private var createAlbumIfNotFound = false
    
    enum PhotoCollectionError: LocalizedError {
        case missingAssetCollection
        case missingAlbumName
        case missingLocalIdentifier
        case unableToFindAlbum(String)
        case unableToLoadSmartAlbum(PHAssetCollectionSubtype)
        case addImageError(Error)
        case createAlbumError(Error)
        case removeAllError(Error)
    }
    
    init(albumNamed albumName: String, createIfNotFound: Bool = false) {
        self.albumName = albumName
        self.createAlbumIfNotFound = createIfNotFound
        super.init()
    }

    init?(albumWithIdentifier identifier: String) {
        guard let assetCollection = PhotoCollection.getAlbum(identifier: identifier) else {
            print("Photo album not found for identifier: \(identifier)")
            return nil
        }
        print("Loaded photo album with identifier: \(identifier)")
        self.assetCollection = assetCollection
        super.init()
        Task {
            await refreshPhotoAssets()
        }
    }
    
    init?(smartAlbum smartAlbumType: PHAssetCollectionSubtype) {
        self.smartAlbumType = smartAlbumType
        super.init()
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func load() async throws {
        
        PHPhotoLibrary.shared().register(self)
        
        if let smartAlbumType = smartAlbumType {
            if let assetCollection = PhotoCollection.getSmartAlbum(subtype: smartAlbumType) {
                print("Loaded smart album of type: \(smartAlbumType.rawValue)")
                self.assetCollection = assetCollection
                await refreshPhotoAssets()
                return
            } else {
                print("Unable to load smart album of type: : \(smartAlbumType.rawValue)")
                throw PhotoCollectionError.unableToLoadSmartAlbum(smartAlbumType)
            }
        }
        
        guard let name = albumName, !name.isEmpty else {
            print("Unable to load an album without a name.")
            throw PhotoCollectionError.missingAlbumName
        }
        
        if let assetCollection = PhotoCollection.getAlbum(named: name) {
            print("Loaded photo album named: \(name)")
            self.assetCollection = assetCollection
            await refreshPhotoAssets()
            return
        }
        
        guard createAlbumIfNotFound else {
            print("Unable to find photo album named: \(name)")
            throw PhotoCollectionError.unableToFindAlbum(name)
        }

        print("Creating photo album named: \(name)")
        
        if let assetCollection = try? await PhotoCollection.createAlbum(named: name) {
            self.assetCollection = assetCollection
            await refreshPhotoAssets()
        }
    }

    func addImage(_ imageData: Data) async throws {
        guard let assetCollection = self.assetCollection else {
            throw PhotoCollectionError.missingAssetCollection
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                
                let creationRequest = PHAssetCreationRequest.forAsset()
                if let assetPlaceholder = creationRequest.placeholderForCreatedAsset {
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                    
                    if let albumChangeRequest = PHAssetCollectionChangeRequest(for: assetCollection), assetCollection.canPerform(.addContent) {
                        let fastEnumeration = NSArray(array: [assetPlaceholder])
                        albumChangeRequest.addAssets(fastEnumeration)
                    }
                }
            }
            
            await refreshPhotoAssets()
            
        } catch let error {
            print("Error adding image to photo library: \(error.localizedDescription)")
            throw PhotoCollectionError.addImageError(error)
        }
    }
    
    @MainActor private func refreshPhotoAssets(_ fetchResult: PHFetchResult<PHAsset>? = nil) async {

        var newFetchResult = fetchResult

        if newFetchResult == nil {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            if let assetCollection = self.assetCollection, let fetchResult = (PHAsset.fetchAssets(in: assetCollection, options: fetchOptions) as AnyObject?) as? PHFetchResult<PHAsset> {
                newFetchResult = fetchResult
            }
        }
        
        if let newFetchResult = newFetchResult {
            await MainActor.run {
                photoAssets = PhotoAssetCollection(newFetchResult)
                print("PhotoCollection photoAssets refreshed: \(self.photoAssets.count)")
            }
        }
    }

    private static func getAlbum(identifier: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: fetchOptions)
        return collections.firstObject
    }
    
    private static func getAlbum(named name: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", name)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        return collections.firstObject
    }
    
    private static func getSmartAlbum(subtype: PHAssetCollectionSubtype) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: fetchOptions)
        return collections.firstObject
    }
    
    private static func createAlbum(named name: String) async throws -> PHAssetCollection? {
        var collectionPlaceholder: PHObjectPlaceholder?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                collectionPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
            }
        } catch let error {
            print("Error creating album in photo library: \(error.localizedDescription)")
            throw PhotoCollectionError.createAlbumError(error)
        }
        print("Created photo album named: \(name)")
        guard let collectionIdentifier = collectionPlaceholder?.localIdentifier else {
            throw PhotoCollectionError.missingLocalIdentifier
        }
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [collectionIdentifier], options: nil)
        return collections.firstObject
    }
}

extension PhotoCollection: PHPhotoLibraryChangeObserver {
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let changes = changeInstance.changeDetails(for: self.photoAssets.fetchResult) else { return }
        Task { @MainActor in
            let changesNoError = changes
            await self.refreshPhotoAssets(changesNoError.fetchResultAfterChanges)
        }
    }
}

