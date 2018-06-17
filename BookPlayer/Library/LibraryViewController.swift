//
//  LibraryViewController.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 7/7/16.
//  Copyright © 2016 Tortuga Power. All rights reserved.
//

import UIKit
import MediaPlayer
import MBProgressHUD
import SwiftReorder

class LibraryViewController: BaseListViewController, UIGestureRecognizerDelegate {
    @IBOutlet weak var emptyLibraryPlaceholder: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // enables pop gesture on pushed controller
        self.navigationController!.interactivePopGestureRecognizer!.delegate = self

        // register for appDelegate openUrl notifications
        NotificationCenter.default.addObserver(self, selector: #selector(self.openURL(_:)), name: Notification.Name.AudiobookPlayer.openURL, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.reloadData), name: Notification.Name.AudiobookPlayer.bookDeleted, object: nil)

        self.loadLibrary()

        guard let identifier = UserDefaults.standard.string(forKey: UserDefaultsConstants.lastPlayedBook),
            let lastPlayedBook = DataManager.getBook(from: identifier) else {
                return
        }

        // Preload player
        PlayerManager.shared.load([lastPlayedBook]) { (loaded) in
            guard loaded else {
                return
            }

            self.showPlayerView(book: lastPlayedBook)
        }
    }

    // No longer need to deregister observers for iOS 9+!
    // https://developer.apple.com/library/mac/releasenotes/Foundation/RN-Foundation/index.html#10_11NotificationCenter
    deinit {
        //for iOS 8
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    /**
     *  Load local files and process them (rename them if necessary)
     *  Spaces in file names can cause side effects when trying to load the data
     */
    func loadLibrary() {
        //load local files
        let loadingWheel = MBProgressHUD.showAdded(to: self.view, animated: true)
        loadingWheel?.labelText = "Loading Books"

        self.library = DataManager.getLibrary()

        //show/hide instructions view
        self.emptyLibraryPlaceholder.isHidden = !self.items.isEmpty
        self.tableView.reloadData()

        DataManager.processPendingFiles { (urls) in
            guard !urls.isEmpty else {
                MBProgressHUD.hideAllHUDs(for: self.view, animated: true)
                return
            }

            DataManager.insertBooks(from: urls, into: self.library) {
                MBProgressHUD.hideAllHUDs(for: self.view, animated: true)

                //show/hide instructions view
                self.emptyLibraryPlaceholder.isHidden = !self.items.isEmpty
                self.tableView.reloadData()
            }
        }
    }

    override func loadFile(urls: [URL]) {
        DataManager.insertBooks(from: urls, into: self.library) {
            MBProgressHUD.hideAllHUDs(for: self.view, animated: true)
            self.emptyLibraryPlaceholder.isHidden = !self.items.isEmpty
            self.tableView.reloadData()
        }
    }

    @objc func openURL(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let fileURL = userInfo["fileURL"] as? URL else {
                return
        }

        MBProgressHUD.showAdded(to: self.view, animated: true)
        
        let destinationFolder = DataManager.getProcessedFolderURL()
        
        guard let bookUrl = DataManager.processFile(at: fileURL, destinationFolder: destinationFolder) else {
            MBProgressHUD.hideAllHUDs(for: self.view, animated: true)
            return
        }
        
        self.loadFile(urls: [bookUrl])
    }

    @objc func reloadData() {
        self.tableView.reloadData()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return navigationController!.viewControllers.count > 1
    }

    func handleDelete(book: Book, indexPath: IndexPath) {
        let alert = UIAlertController(title: "Delete \(book.title!)?", message: "Do you really want to delete this book?", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            self.tableView.setEditing(false, animated: true)
        }))

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            do {
                if book == PlayerManager.shared.currentBook {
                    PlayerManager.shared.stop()
                }

                self.library.removeFromItems(book)

                DataManager.saveContext()

                try FileManager.default.removeItem(at: book.fileURL)

                self.tableView.beginUpdates()
                self.tableView.deleteRows(at: [indexPath], with: .none)
                self.tableView.endUpdates()
                self.emptyLibraryPlaceholder.isHidden = !self.items.isEmpty
            } catch {
                self.showAlert("Error", message: "There was an error deleting the file, please try again.")
            }
        }))

        alert.popoverPresentationController?.sourceView = self.view
        alert.popoverPresentationController?.sourceRect = CGRect(x: Double(self.view.bounds.size.width / 2.0), y: Double(self.view.bounds.size.height-45), width: 1.0, height: 1.0)

        self.present(alert, animated: true, completion: nil)
    }

    func handleDelete(playlist: Playlist, indexPath: IndexPath) {
        let sheet = UIAlertController(
            title: "Delete \(playlist.title!)?",
            message: "Deleting only the playlist will move all its files back to the Library.",
            preferredStyle: .alert
        )

        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        sheet.addAction(UIAlertAction(title: "Delete playlist only", style: .default, handler: { _ in
            if let orderedSet = playlist.books {
                self.library.addToItems(orderedSet)
            }
            self.library.removeFromItems(playlist)
            DataManager.saveContext()

            self.tableView.beginUpdates()
            self.tableView.reloadSections(IndexSet(integer: 0), with: .fade)
            self.tableView.endUpdates()
            self.emptyLibraryPlaceholder.isHidden = !self.items.isEmpty
        }))

        sheet.addAction(UIAlertAction(title: "Delete both playlist and books", style: .destructive, handler: { _ in
            do {

                self.library.removeFromItems(playlist)
                DataManager.saveContext()

                // swiftlint:disable force_cast
                for book in playlist.books?.array as! [Book] {
                    try FileManager.default.removeItem(at: book.fileURL)
                }

                self.tableView.beginUpdates()
                self.tableView.deleteRows(at: [indexPath], with: .none)
                self.tableView.endUpdates()
                self.emptyLibraryPlaceholder.isHidden = !self.items.isEmpty
            } catch {
                self.showAlert("Error", message: "There was an error deleting the book, please try again.")
            }
        }))

        self.present(sheet, animated: true, completion: nil)
    }

    func presentCreatePlaylistAlert(_ namePlaceholder: String = "Name", handler: ((_ title: String) -> Void)?) {
        let playlistAlert = UIAlertController(
            title: "Create a new playlist",
            message: "Files in playlists are automatically played one after the other",
            preferredStyle: .alert
        )

        playlistAlert.addTextField(configurationHandler: { (textfield) in
            textfield.placeholder = namePlaceholder
        })

        playlistAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        playlistAlert.addAction(UIAlertAction(title: "Create", style: .default, handler: { _ in
            let title = playlistAlert.textFields!.first!.text!

            handler?(title)
        }))

        self.present(playlistAlert, animated: true, completion: nil)
    }

    @IBAction func addAction() {
        let alertController = UIAlertController(
            title: nil,
            message: "You can also add files via AirDrop. Send an audiobook file to your device and select BookPlayer from the list that appears.",
            preferredStyle: .actionSheet
        )

        alertController.addAction(UIAlertAction(title: "Import files", style: .default) { (_) in
            self.presentImportFilesAlert()
        })

        alertController.addAction(UIAlertAction(title: "Create playlist", style: .default) { (_) in
            self.presentCreatePlaylistAlert(handler: { title in
                let playlist = DataManager.createPlaylist(title: title, books: [])

                self.library.addToItems(playlist)

                DataManager.saveContext()

                self.tableView.reloadData()
            })
        })

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        self.present(alertController, animated: true, completion: nil)
    }
}

extension LibraryViewController {
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard indexPath.section == 0 else {
            return nil
        }

        let item = self.items[indexPath.row]

        // "…" on a button indicates a follow up dialog instead of an immmediate action in macOS and iOS
        let deleteAction = UITableViewRowAction(style: .default, title: "Delete…") { (_, indexPath) in
            guard let book = self.items[indexPath.row] as? Book else {
                guard let playlist = self.items[indexPath.row] as? Playlist else {
                    return
                }

                self.handleDelete(playlist: playlist, indexPath: indexPath)

                return
            }

            self.handleDelete(book: book, indexPath: indexPath)
        }

        deleteAction.backgroundColor = .red

        if item is Playlist {
            let renameAction = UITableViewRowAction(style: .normal, title: "Rename") { (_, indexPath) in
                guard let playlist = self.items[indexPath.row] as? Playlist else {
                    return
                }

                let alert = UIAlertController(title: "Rename playlist", message: nil, preferredStyle: .alert)

                alert.addTextField(configurationHandler: { (textfield) in
                    textfield.placeholder = playlist.title
                    textfield.text = playlist.title
                })

                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                alert.addAction(UIAlertAction(title: "Rename", style: .default) { _ in
                    if let title = alert.textFields!.first!.text, title != playlist.title {
                        playlist.title = title

                        DataManager.saveContext()

                        self.tableView.reloadData()
                    }
                })

                self.present(alert, animated: true, completion: nil)
            }

            return [deleteAction, renameAction]
        }

        return [deleteAction]
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.section == 0 else {
            self.addAction()

            return
        }

        let item = self.items[indexPath.row]

        guard let book = item as? Book else {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)

            if let playlist = item as? Playlist, let playlistVC = storyboard.instantiateViewController(withIdentifier: "PlaylistViewController") as? PlaylistViewController {
                playlistVC.library = self.library
                playlistVC.playlist = playlist

                self.navigationController?.pushViewController(playlistVC, animated: true)
            }

            return
        }

        self.setupPlayer(books: [book])
    }
}

extension LibraryViewController {
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)

        guard let bookCell = cell as? BookCellView,
            PlayerManager.shared.currentBook != nil,
            let index = self.library.itemIndex(with: PlayerManager.shared.currentBook.fileURL),
            index == indexPath.row else {
                return cell
        }

        bookCell.titleColor = UIColor(red: 0.37, green: 0.64, blue: 0.85, alpha: 1.0)
        bookCell.artworkButton.setImage(#imageLiteral(resourceName: "playerIconPlay"), for: .normal)

        return bookCell
    }
    override func tableView(_ tableView: UITableView, reorderRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard destinationIndexPath.section == 0 else {
            return
        }

        let item = self.items[sourceIndexPath.row]

        self.library.removeFromItems(at: sourceIndexPath.row)
        self.library.insertIntoItems(item, at: destinationIndexPath.row)

        DataManager.saveContext()
    }

    override func tableViewDidFinishReordering(_ tableView: UITableView, from initialSourceIndexPath: IndexPath, to finalDestinationIndexPath: IndexPath, dropped overIndexPath: IndexPath?) {
        guard let overIndexPath = overIndexPath, overIndexPath.section == 0, let book = self.items[finalDestinationIndexPath.row] as? Book else {
            return
        }

        let item = self.items[overIndexPath.row]

        if item is Playlist {
            let alert = UIAlertController(
                title: "Move to playlist",
                message: "Do you want to move \(book.title!) to \(item.title!)?",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

            alert.addAction(UIAlertAction(title: "Move", style: .default, handler: { (_) in
                if let playlist = item as? Playlist {
                    playlist.addToBooks(book)
                }

                self.library.removeFromItems(at: finalDestinationIndexPath.row)

                DataManager.saveContext()

                self.tableView.beginUpdates()
                self.tableView.deleteRows(at: [finalDestinationIndexPath], with: .fade)
                self.tableView.reloadRows(at: [overIndexPath], with: .fade)
                self.tableView.endUpdates()
            }))

            self.present(alert, animated: true, completion: nil)
        } else {
            self.presentCreatePlaylistAlert(handler: { title in
                let minIndex = min(finalDestinationIndexPath.row, overIndexPath.row)

                // Removing based on minIndex works because the cells are always adjacent
                let book1 = self.items[minIndex]

                self.library.removeFromItems(book1)

                let book2 = self.items[minIndex]

                self.library.removeFromItems(book2)

                // swiftlint:disable force_cast
                let books = [book1 as! Book, book2 as! Book]
                let playlist = DataManager.createPlaylist(title: title, books: books)

                self.library.insertIntoItems(playlist, at: minIndex)

                DataManager.saveContext()

                self.tableView.beginUpdates()
                self.tableView.deleteRows(at: [IndexPath(row: minIndex, section: 0), IndexPath(row: minIndex + 1, section: 0)], with: .fade)
                self.tableView.insertRows(at: [IndexPath(row: minIndex, section: 0)], with: .fade)
                self.tableView.endUpdates()
            })
        }
    }
}
