import Combine
import Foundation

/// Wires a `ProfileListModel` to a real `ProfileStore` (TASK-06).
///
/// `ProfileListModel` deliberately does not depend on `ProfileStore`'s
/// concrete type — see its own doc comment — so this is the one place that
/// bridges the two: it mirrors the store's `@Published profiles` and
/// `selectedProfileID` onto the model, and forwards every action straight
/// through to the store.
///
/// `ProfileStore.add` auto-selects the newly created profile (FR-1.10) and
/// `ProfileStore.delete` auto-reassigns the selection when it removes the
/// selected profile (FR-1.8). Both already publish through
/// `selectedProfileID`, which this adapter mirrors — so neither behavior is
/// repeated here.
extension ProfileListModel {
    /// Creates a list model that reflects and drives `store`.
    ///
    /// The returned model retains the Combine subscriptions for its own
    /// lifetime (`storeSubscriptions`), so callers do not need to hold onto
    /// anything beyond the model itself.
    @MainActor
    static func adapting(to store: ProfileStore, calendar: Calendar = .autoupdatingCurrent) -> ProfileListModel {
        let model = ProfileListModel(
            profiles: store.profiles,
            selectedProfileID: store.selectedProfileID,
            calendar: calendar,
            addProfile: { try store.add($0) },
            updateProfile: { try store.update($0) },
            deleteProfile: { try store.delete(id: $0) },
            selectProfile: { store.select(id: $0) }
        )
        model.bindToStorePublishers(store)
        return model
    }

    /// Mirrors `store`'s published state onto `self` for as long as `self`
    /// (and therefore `storeSubscriptions`) is alive.
    private func bindToStorePublishers(_ store: ProfileStore) {
        store.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profiles in
                self?.profiles = profiles
            }
            .store(in: &storeSubscriptions)

        store.$selectedProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedProfileID in
                self?.selectedProfileID = selectedProfileID
            }
            .store(in: &storeSubscriptions)
    }
}
