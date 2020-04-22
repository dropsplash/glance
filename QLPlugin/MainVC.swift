import Cocoa
import os.log
import Quartz

enum PreviewError: Error {
	case fileSizeError(path: String)
}

extension PreviewError: LocalizedError {
	public var errorDescription: String? {
		switch self {
			case let .fileSizeError(path):
				return NSLocalizedString("File \(path) is too large to preview", comment: "")
		}
	}
}

class MainVC: NSViewController, QLPreviewingController {
	/// Max size of files to render
	let maxFileSize = 10_000_000 // 10 MB

	let stats = Stats()

	override var nibName: NSNib.Name? {
		NSNib.Name("MainVC")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		setUpView()
	}

	private func setUpView() {
		// Draw border around previews, in similar style to macOS's default previews
		view.wantsLayer = true
		view.layer?.borderWidth = 1
		view.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
	}

	/// Function responsible for generating file previews. It's called for previews in Finder,
	/// Spotlight, Quick Look and any other UI elements which implement the API
	func preparePreviewOfFile(
		at fileUrl: URL,
		completionHandler handler: @escaping (Error?) -> Void
	) {
		DispatchQueue.main.async {
			// Read information about the file to preview
			var file: File
			do {
				file = try File(url: fileUrl)
			} catch {
				handler(error)
				return
			}

			// Skip preview if the file is too large
			if !file.isDirectory, !file.isArchive, file.size > self.maxFileSize {
				// Log error and fall back to default preview (by calling the completion handler
				// with the error)
				handler(PreviewError.fileSizeError(path: file.path))
				return
			}

			// Render file preview
			os_log(
				"Generating preview for file %{public}s",
				log: Log.general,
				type: .info,
				file.path
			)
			do {
				try self.previewFile(file: file)
			} catch {
				// Log error and fall back to default preview (by calling the completion handler
				// with the error)
				handler(error)
				return
			}

			// Update stats
			self.stats.increaseStatsCounts(fileExtension: file.url.pathExtension)

			// Hide preview loading spinner
			handler(nil)
		}
	}

	/// Generates a preview of the selected file and adds the corresponding child view controller
	private func previewFile(file: File) throws {
		// Initialize `PreviewVC` for the file type
		if let previewVCType = PreviewVCFactory.getView(fileURL: file.url) {
			// Generate file preview
			let previewVC = previewVCType.init(file: file)
			try previewVC.loadPreview()

			// Add `PreviewVC` as a child view controller
			addChild(previewVC)
			previewVC.view.autoresizingMask = [.height, .width]
			previewVC.view.frame = view.frame
			view.addSubview(previewVC.view)
		} else {
			os_log(
				"Skipping preview for file %{public}s: File type not supported",
				log: Log.general,
				type: .info,
				file.path
			)
		}
	}
}
