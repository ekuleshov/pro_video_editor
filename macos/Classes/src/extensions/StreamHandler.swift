import FlutterMacOS

/// FlutterStreamHandler conformance for ProVideoEditorPlugin.
///
/// Manages the event channel for progress updates.
/// Progress events are streamed to Flutter with task ID and progress value (0.0 to 1.0).
extension ProVideoEditorPlugin: FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
