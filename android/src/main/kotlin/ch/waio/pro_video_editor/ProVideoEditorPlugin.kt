package ch.waio.pro_video_editor

import android.os.Handler
import android.os.Looper
import android.util.Log
import ch.waio.pro_video_editor.src.features.metadata.Metadata
import ch.waio.pro_video_editor.src.features.metadata.models.MetadataConfig
import ch.waio.pro_video_editor.src.features.render.RenderVideo
import ch.waio.pro_video_editor.src.features.render.models.RenderConfig
import ch.waio.pro_video_editor.src.features.render.models.RenderTask
import ch.waio.pro_video_editor.src.features.thumbnail.ThumbnailGenerator
import ch.waio.pro_video_editor.src.features.thumbnail.models.ThumbnailConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.util.concurrent.ConcurrentHashMap

/**
 * ProVideoEditorPlugin - Main Flutter plugin for advanced video editing capabilities.
 *
 * This plugin provides a comprehensive set of video processing features including:
 * - Video rendering with effects (rotation, flip, scale, color adjustments, blur)
 * - Video metadata extraction (dimensions, duration, bitrate, tags)
 * - Thumbnail generation (timestamp-based or keyframe extraction)
 * - Progress tracking via event channels
 * - Cancellable operations for all long-running tasks
 *
 * The plugin uses a feature-based architecture where each capability is handled
 * by a dedicated service class (RenderVideo, Metadata, ThumbnailGenerator).
 * All operations are asynchronous with callback-based APIs to prevent blocking
 * the Flutter UI thread.
 *
 * Communication protocol:
 * - Method channel: "pro_video_editor" for commands and responses
 * - Event channel: "pro_video_editor_progress" for progress updates
 */
class ProVideoEditorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private lateinit var renderVideo: RenderVideo
    private lateinit var metadata: Metadata
    private lateinit var thumbnailGenerator: ThumbnailGenerator

    private val mainHandler = Handler(Looper.getMainLooper())
    private val activeRenderTasks = ConcurrentHashMap<String, RenderTask>()

    /**
     * Called when the plugin is attached to a Flutter engine.
     *
     * Initializes all communication channels and service instances.
     * This is the entry point for plugin lifecycle management.
     *
     * @param flutterPluginBinding Binding providing access to application context and messenger
     */
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "pro_video_editor")
        eventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "pro_video_editor_progress")

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        renderVideo = RenderVideo(flutterPluginBinding.applicationContext)
        metadata = Metadata(flutterPluginBinding.applicationContext)
        thumbnailGenerator = ThumbnailGenerator(flutterPluginBinding.applicationContext)
    }

    /**
     * Called when the plugin is detached from the Flutter engine.
     *
     * Cleans up all communication channels to prevent memory leaks.
     * Active render tasks are not automatically canceled.
     *
     * @param binding Binding information for cleanup
     */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    /**
     * Routes incoming method calls to appropriate handlers.
     *
     * Available methods:
     * - getPlatformVersion: Returns Android version
     * - getMetadata: Extracts video metadata
     * - getThumbnails: Generates thumbnails
     * - renderVideo: Renders video with effects
     * - cancelTask: Cancels active render task
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> handleGetPlatformVersion(result)
            "getMetadata" -> handleGetMetadata(call, result)
            "getThumbnails" -> handleGetThumbnails(call, result)
            "renderVideo" -> handleRenderVideo(call, result)
            "cancelTask" -> handleCancelTask(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Returns the Android platform version string.
     */
    private fun handleGetPlatformVersion(result: MethodChannel.Result) {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
    }

    /**
     * Extracts metadata from a video file asynchronously.
     *
     * Retrieves technical properties (duration, dimensions, bitrate)
     * and descriptive tags (title, artist, album, etc.).
     */
    private fun handleGetMetadata(call: MethodCall, result: MethodChannel.Result) {
        try {
            val config = MetadataConfig.fromMethodCall(call)
            metadata.getMetadata(
                config = config,
                onComplete = { meta ->
                    mainHandler.post {
                        result.success(meta)
                    }
                },
                onError = { error ->
                    mainHandler.post {
                        result.error("METADATA_ERROR", error.message, null)
                    }
                }
            )
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ARGUMENTS", e.message, null)
        }
    }

    /**
     * Generates thumbnail images from a video asynchronously.
     *
     * Supports timestamp-based or keyframe-based extraction.
     * Thumbnails are generated in parallel for optimal performance.
     */
    private fun handleGetThumbnails(call: MethodCall, result: MethodChannel.Result) {
        try {
            val config = ThumbnailConfig.fromMethodCall(call)
            postProgress(config.id, 0.0)

            thumbnailGenerator.getThumbnails(
                config = config,
                onProgress = { progress -> postProgress(config.id, progress) },
                onComplete = { thumbnails ->
                    mainHandler.post {
                        postProgress(config.id, 1.0)
                        result.success(thumbnails)
                    }
                },
                onError = { error ->
                    mainHandler.post {
                        result.error("THUMBNAIL_ERROR", error.message, null)
                    }
                }
            )
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ARGUMENTS", e.message, null)
        }
    }

    /**
     * Starts an asynchronous video render job with effects.
     *
     * Handles video concatenation, visual effects (rotation, flip,
     * scale, color, blur), audio processing, and output configuration.
     * Each job is tracked by unique ID and can be canceled.
     */
    private fun handleRenderVideo(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: ""
        if (id.isBlank()) {
            result.error("INVALID_ARGUMENTS", "Task id is required and cannot be empty", null)
            return
        }

        if (activeRenderTasks.containsKey(id)) {
            result.error(
                "TASK_ALREADY_EXISTS",
                "A render task with id '$id' is already active",
                null
            )
            return
        }

        postProgress(id, 0.0)

        val task = RenderTask(job = null, result = result)
        activeRenderTasks[id] = task

        try {
            val renderConfig = RenderConfig.fromMethodCall(call)

            val jobHandle = renderVideo.render(
                config = renderConfig,
                onProgress = { progress -> postProgress(id, progress) },
                onComplete = { resultBytes ->
                    mainHandler.post {
                        postProgress(id, 1.0)
                        val removedTask = activeRenderTasks.remove(id)
                        removedTask?.sendSuccess(resultBytes)
                    }
                },
                onError = { error ->
                    Log.e("RenderVideo", "Error rendering video: ${error.message}")
                    mainHandler.post {
                        val removedTask = activeRenderTasks.remove(id)
                        val code = if (removedTask?.canceled?.get() == true) {
                            "CANCELED"
                        } else {
                            "RENDER_ERROR"
                        }
                        removedTask?.sendError(code, error.message)
                    }
                }
            )

            task.job = jobHandle
            if (task.canceled.get()) {
                jobHandle.cancel()
            }
        } catch (e: IllegalArgumentException) {
            activeRenderTasks.remove(id)
            result.error("INVALID_ARGUMENTS", e.message, null)
        } catch (e: Exception) {
            activeRenderTasks.remove(id)
            result.error("RENDER_ERROR", "Failed to start render: ${e.message}", null)
        }
    }

    /**
     * Cancels an active render task by ID.
     *
     * Marks task as canceled, triggers cancellation handler
     * (stops transformer, cleans up files), and removes from tracking.
     */
    private fun handleCancelTask(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: ""
        if (id.isBlank()) {
            result.error("INVALID_ARGUMENTS", "Task id is required and cannot be empty", null)
            return
        }

        val task = activeRenderTasks[id]
        if (task == null) {
            result.error("TASK_NOT_FOUND", "No active render task found with id '$id'", null)
            return
        }

        task.canceled.set(true)
        task.job?.cancel()
        activeRenderTasks.remove(id)
        result.success(true)
    }

    /**
     * Sends progress updates to Flutter via event channel.
     *
     * Progress events are sent on main thread with task ID
     * and progress value (0.0 to 1.0).
     */
    private fun postProgress(id: String, progress: Double) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "id" to id,
                    "progress" to progress
                )
            )
        }
    }
}
