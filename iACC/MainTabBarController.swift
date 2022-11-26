//
// Copyright © Essential Developer. All rights reserved.
//

import UIKit

class MainTabBarController: UITabBarController {
    
    private var friendsCache: FriendsCache!
    
    convenience init(friendsCache: FriendsCache) {
        self.init(nibName: nil, bundle: nil)
        self.friendsCache = friendsCache
        self.setupViewController()
    }

    private func setupViewController() {
        viewControllers = [
            makeNav(for: makeFriendsList(), title: "Friends", icon: "person.2.fill"),
            makeTransfersList(),
            makeNav(for: makeCardsList(), title: "Cards", icon: "creditcard.fill")
        ]
    }
    
    private func makeNav(for vc: UIViewController, title: String, icon: String) -> UIViewController {
        vc.navigationItem.largeTitleDisplayMode = .always
        
        let nav = UINavigationController(rootViewController: vc)
        nav.tabBarItem.image = UIImage(
            systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(scale: .large)
        )
        nav.tabBarItem.title = title
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
    
    private func makeTransfersList() -> UIViewController {
        let sent = makeSentTransfersList()
        sent.navigationItem.title = "Sent"
        sent.navigationItem.largeTitleDisplayMode = .always
        
        let received = makeReceivedTransfersList()
        received.navigationItem.title = "Received"
        received.navigationItem.largeTitleDisplayMode = .always
        
        let vc = SegmentNavigationViewController(first: sent, second: received)
        vc.tabBarItem.image = UIImage(
            systemName: "arrow.left.arrow.right",
            withConfiguration: UIImage.SymbolConfiguration(scale: .large)
        )
        vc.title = "Transfers"
        vc.navigationBar.prefersLargeTitles = true
        return vc
    }
    
    private func makeFriendsList() -> ListViewController {
        let vc = ListViewController()
        vc.title = "Friends"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: vc, action: #selector(addFriend))
        
        let isPremium = User.shared?.isPremium == true
        
        let api = FriendsAPIItemsServicesAdapter(
            api: FriendsAPI.shared,
            cache: isPremium ? friendsCache : NullFriendsCache(),
            select: { [weak vc] item in
                vc?.select(friend: item)
            }).retry(2)
        
        let cache = FriendsCacheItemsServicesAdapter(
            cache: friendsCache,
            select: { [weak vc] item in
                vc?.select(friend: item)
            })
    
        // vc.service = ItemsServicesWithFallback(primary: api, fallback: cache)
//        vc.service = isPremium ? api
//            .fallback(api)
//            .fallback(api)
//            .fallback(cache) : api.fallback(api).fallback(api)
        
        //vc.service = isPremium ? api.retry(2).fallback(cache) : api.retry(2)
        
        vc.service = isPremium ? api.fallback(cache) : api
        
        return vc
    }
    
    private func makeSentTransfersList() -> ListViewController {
        let vc = ListViewController()
        
        vc.navigationItem.title = "Sent"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Send", style: .done, target: vc, action: #selector(sendMoney))
        
        vc.service = SentTransfersAPIItemsServicesAdapter(
            api: TransfersAPI.shared,
            select: { [weak vc] item in
                vc?.select(transfer: item)
            }).retry(1)
        
        return vc
    }
    
    private func makeReceivedTransfersList() -> ListViewController {
        let vc = ListViewController()
        
        vc.navigationItem.title = "Received"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Request", style: .done, target: vc, action: #selector(requestMoney))
        
        vc.service = RecievedTransfersAPIItemsServicesAdapter(
            api: TransfersAPI.shared,
            select: { [weak vc] item in
                vc?.select(transfer: item)
            }).retry(1)
        
        return vc
    }
    
    private func makeCardsList() -> ListViewController {
        let vc = ListViewController()
        vc.title = "Cards"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: vc, action: #selector(addCard))
        
        vc.service = CardAPIItemsServicesAdapter(api: CardAPI.shared, select: { [weak vc] item in
            vc?.select(card: item)
        })
        
        return vc
    }
    
}

extension ItemService {
    func fallback(_ fallback: ItemService) -> ItemService {
        ItemsServicesWithFallback(primary: self, fallback: fallback)
    }
    
    func retry(_ retyCount: UInt) -> ItemService {
        var service: ItemService = self
        for _ in 0..<retyCount {
            service = service.fallback(self)
        }
        return service
    }
}

// Composite
struct ItemsServicesWithFallback: ItemService {
    let primary: ItemService
    let fallback: ItemService
    
    func loadItems(completion: @escaping (Result<[ItemViewModel], Error>) -> Void) {
        primary.loadItems { result in
            switch result {
            case.success:
                completion(result)
            case.failure:
                fallback.loadItems(completion: completion)
            }
        }
    }
}

struct FriendsAPIItemsServicesAdapter: ItemService {
    let api: FriendsAPI
    let cache: FriendsCache
    let select: (Friend) -> Void
    
    func loadItems(completion: @escaping (Result<[ItemViewModel], Error>) -> Void) {
        api.loadFriends { result in
            DispatchQueue.mainAsyncIfNeeded {
                completion(result.map({ items in
                    cache.save(items)
                    return items.map { item in
                        ItemViewModel(friend: item) {
                            select(item)
                        }
                    }
                }))
            }
        }
    }
}

struct FriendsCacheItemsServicesAdapter: ItemService {
    let cache: FriendsCache
    let select: (Friend) -> Void
    
    func loadItems(completion: @escaping (Result<[ItemViewModel], Error>) -> Void) {
        cache.loadFriends { result in
            DispatchQueue.mainAsyncIfNeeded {
                completion(result.map({ items in
                    items.map{ item in
                        ItemViewModel(friend: item, selection: {
                            select(item)
                        })
                    }
                }))
            }
        }
    }
}

// Null Object Pattern
class NullFriendsCache: FriendsCache {
    override func save(_ newFriends: [Friend]) {}
}

struct CardAPIItemsServicesAdapter: ItemService {
    let api: CardAPI
    let select: (Card) -> Void
    
    func loadItems(completion: @escaping (Result<[ItemViewModel], Error>) -> Void) {
        api.loadCards {result in
            DispatchQueue.mainAsyncIfNeeded {
                completion(result.map({ items in
                    items.map { item in
                        ItemViewModel(card: item) {
                            select(item)
                        }
                    }
                }))
            }
        }
    }
}

struct SentTransfersAPIItemsServicesAdapter: ItemService {
    let api: TransfersAPI
    let select: (Transfer) -> Void
    
    func loadItems(completion: @escaping (Result<[ItemViewModel], Error>) -> Void) {
        api.loadTransfers { result in
            DispatchQueue.mainAsyncIfNeeded {
                completion(result.map({ items in
                    items.filter{ $0.isSender } .map { item in
                        ItemViewModel(transfer: item, longDateStyle: true) {
                            select(item)
                        }
                    }
                }))
            }
        }
    }
}

struct RecievedTransfersAPIItemsServicesAdapter: ItemService {
    let api: TransfersAPI
    let select: (Transfer) -> Void
    
    func loadItems(completion: @escaping (Result<[ItemViewModel], Error>) -> Void) {
        api.loadTransfers { result in
            DispatchQueue.mainAsyncIfNeeded {
                completion(result.map({ items in
                    items.filter{ !$0.isSender } .map { item in
                        ItemViewModel(transfer: item, longDateStyle: false) {
                            select(item)
                        }
                    }
                }))
            }
        }
    }
}
