//
//  ContentView.kt
//  AndroidEngineer
//
//  Engineer screen — chip-list prompt builder + result history. Compose port
//  of the SwiftUI Prod ContentView: real backend (chat synthesize → generate →
//  fetch) and disk-backed persistence so runs and chips survive launches.
//

package market.femi.engineer

import android.content.Context
import android.graphics.BitmapFactory
import android.text.format.DateUtils
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.materialIcon
import androidx.compose.material.icons.materialPath
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.BasicFileAttributes
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import market.femi.api.ChatMessage
import market.femi.api.ProjectService
import market.femi.api.Role
import market.femi.api.flux2KleinI2I
import market.femi.api.flux2Pro
import market.femi.api.qwen3_6_35b_a3b
import org.json.JSONArray
import org.json.JSONObject

// MARK: - Models

private data class Chip(
    val id: String = UUID.randomUUID().toString(),
    val text: String,
)

private enum class RunState { Loading, Loaded, Failed }

private data class Run(
    val id: String = UUID.randomUUID().toString(),
    val chips: List<Chip>,
    val state: RunState,
    /** Disk filename under the ProjectService documents root. Empty until loaded. */
    val imageFilename: String = "",
    /** Decoded image, cached after first read so the row doesn't re-decode every render. */
    val image: ImageBitmap? = null,
    val liked: Boolean = false,
    /** Index into [gradientPalettes] — shimmer/failure backdrop and decode fallback. */
    val paletteIndex: Int,
    val createdAt: Long = System.currentTimeMillis(),
)

/**
 * One batch as rendered in the RESULTS section. Grouping is derived from
 * [Run.createdAt] (rounded into a 2-second window) — runs that landed from
 * one Generate tap share a bucket. [id] just gives the list stable identity.
 */
private data class RunBatch(
    val id: String,
    val createdAt: Long,
    val runs: List<Run>,
)

private data class PendingUndo(
    val id: String = UUID.randomUUID().toString(),
    val run: Run,
    val index: Int,
)

// MARK: - Persistence
//
// Source of truth is the disk via ProjectService. Each row is one PNG under
// the documents root with chips embedded as IPTC keywords, the joined prompt
// as IPTC Caption/Abstract, the model as TIFF Software, and the like state as
// IPTC StarRating. The editor's working chip set lives separately in
// SharedPreferences because it's not a generation, just typing in progress.

private object Store {
    private const val CHIPS_KEY = "engineerChips.v1"

    private fun prefs(context: Context) =
        context.getSharedPreferences("engineer", Context.MODE_PRIVATE)

    fun loadChips(context: Context): List<Chip> {
        val raw = prefs(context).getString(CHIPS_KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Chip(id = o.getString("id"), text = o.getString("text"))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveChips(context: Context, chips: List<Chip>) {
        val arr = JSONArray()
        for (chip in chips) arr.put(JSONObject().put("id", chip.id).put("text", chip.text))
        prefs(context).edit { putString(CHIPS_KEY, arr.toString()) }
    }

    /** Resolves a filename through ProjectService so we share its path convention. */
    private suspend fun fileFor(filename: String): File =
        File(ProjectService.getUrl(filename).removePrefix("file://"))

    /**
     * Walks the documents root via ProjectService and reconstructs Runs from
     * each PNG's embedded XMP (subject keywords → chips, rating → liked) plus
     * the file's creation date. Newest first. No sidecar — the disk IS the index.
     */
    suspend fun loadRuns(): List<Run> = withContext(Dispatchers.IO) {
        ProjectService.getAllGenerations()
            .map { it.substringAfterLast('/') }
            .filter { it.substringAfterLast('.', "").lowercase() == "png" }
            .mapNotNull { filename ->
                val file = fileFor(filename)
                val bytes = runCatching { file.readBytes() }.getOrNull() ?: return@mapNotNull null
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@mapNotNull null
                val chipTexts = ProjectService.getSubject(filename) ?: emptyList()
                val liked = ProjectService.getLike(filename)
                val createdAt = runCatching {
                    Files.readAttributes(file.toPath(), BasicFileAttributes::class.java)
                        .creationTime().toMillis()
                }.getOrNull() ?: file.lastModified().takeIf { it > 0 } ?: System.currentTimeMillis()
                val stem = filename.substringBeforeLast('.')
                val runId = runCatching { UUID.fromString(stem).toString() }
                    .getOrNull() ?: UUID.randomUUID().toString()
                Run(
                    id = runId,
                    chips = chipTexts.map { Chip(text = it) },
                    state = RunState.Loaded,
                    imageFilename = filename,
                    image = bmp.asImageBitmap(),
                    liked = liked,
                    paletteIndex = filename.hashCode() and Int.MAX_VALUE,
                    createdAt = createdAt,
                )
            }
            .sortedByDescending { it.createdAt }
    }

    /**
     * Persists the generated bytes with chips embedded as IPTC keywords,
     * joined prompt as Caption/Abstract, and the model name as TIFF Software.
     * [model] is honest about which path produced this image — "Flux2Pro" in
     * default mode, "Flux2KleinI2I" in cast mode. Returns the on-disk filename.
     */
    suspend fun saveRun(
        data: ByteArray,
        runId: String,
        chips: List<Chip>,
        model: String,
    ): String {
        val filename = "$runId.png"
        ProjectService.saveFile(
            data,
            named = filename,
            prompt = chips.joinToString(", ") { it.text },
            model = model,
            subject = chips.map { it.text },
        )
        return filename
    }

    suspend fun setLiked(filename: String, liked: Boolean) = ProjectService.like(filename, liked)

    /**
     * ProjectService doesn't expose a delete primitive; resolve the path
     * through it so we share the same convention, then unlink.
     */
    suspend fun deleteImage(filename: String) {
        if (filename.isEmpty()) return
        val file = fileFor(filename)
        withContext(Dispatchers.IO) { runCatching { file.delete() } }
    }
}

// MARK: - Image service (real backend)
//
// Direct top-level suspend functions from the Api artifact, Rust FFI under the
// hood. No HTTP client and no base64 plumbing beyond encoding the cast
// reference bytes. Each function returns bytes directly — on lib-level failure
// the bytes will be the sentinel fallback/topup PNG, which renders as a
// regular result. Failure path still triggers if the bytes can't be decoded.

private class ImageServiceException(message: String) : Exception(message)

private object ImageService {
    private var user: String = ""
    private var password: String = ""

    fun configure(user: String, password: String) {
        this.user = user
        this.password = password
    }

    private suspend fun readProjectFile(filename: String): ByteArray? = withContext(Dispatchers.IO) {
        runCatching {
            File(ProjectService.getUrl(filename).removePrefix("file://")).readBytes()
        }.getOrNull()
    }

    /**
     * Cast mode: pass both reference files as base64 and let the Rust FFI
     * handle the rest. Caller pre-synthesizes the prompt.
     */
    suspend fun castGenerate(
        prompt: String,
        characterFilename: String,
        targetFilename: String,
    ): Pair<ByteArray, String> {
        val characterData = readProjectFile(characterFilename)
        val targetData = readProjectFile(targetFilename)
        if (characterData == null || targetData == null) {
            throw ImageServiceException("couldn't read cast reference bytes")
        }
        val encoder = java.util.Base64.getEncoder()
        val result = flux2KleinI2I(
            user = user,
            pass = password,
            imageB64 = encoder.encodeToString(characterData),
            image2B64 = encoder.encodeToString(targetData),
            prompt = prompt,
        )
        return result to "${UUID.randomUUID()}.png"
    }

    /**
     * Chat synthesis via Qwen. Runs on every Generate regardless of mode —
     * Engineer treats synthesis as universal. Returns the last assistant
     * message; falls back to the original idea if the model returned nothing.
     */
    suspend fun chatSynthesize(idea: String): String {
        val userIdea = idea.ifEmpty { "Surprise me — generate something interesting." }
        val synthesizerRequest =
            "Make image prompt frame for Flux2. Reply with only the prompt, nothing else.\n" +
                "Idea: $userIdea"
        val messages = qwen3_6_35b_a3b(
            user = user,
            pass = password,
            messages = listOf(ChatMessage(Role.User, synthesizerRequest)),
        )
        return messages.lastOrNull { it.role == Role.Assistant }
            ?.content?.takeIf { it.isNotEmpty() }
            ?: userIdea
    }

    /** Default text-to-image via Flux2Pro. Caller supplies a pre-synthesized prompt. */
    suspend fun generate(prompt: String): Pair<ByteArray, String> =
        flux2Pro(user = user, pass = password, prompt = prompt) to "${UUID.randomUUID()}.png"
}

// MARK: - Constants

private val Purple = Color(red = 0.55f, green = 0.20f, blue = 1.0f)
private val Pink = Color(red = 1.0f, green = 0.30f, blue = 0.65f)
private val PinkGlow = Color(red = 0.95f, green = 0.30f, blue = 0.65f)

private val gradientPalettes: List<List<Color>> = listOf(
    listOf(Color(1.00f, 0.50f, 0.30f), Color(0.80f, 0.20f, 0.50f)),
    listOf(Color(0.30f, 0.50f, 1.00f), Color(0.60f, 0.20f, 0.90f)),
    listOf(Color(0.95f, 0.60f, 0.20f), Color(0.70f, 0.30f, 0.70f)),
    listOf(Color(0.20f, 0.60f, 0.70f), Color(0.50f, 0.80f, 0.50f)),
    listOf(Color(0.60f, 0.20f, 0.40f), Color(0.90f, 0.40f, 0.60f)),
    listOf(Color(0.15f, 0.25f, 0.45f), Color(0.70f, 0.45f, 0.65f)),
)

private val presets = listOf("Cinematic", "Neon", "Moody", "Pastel", "Film", "Surreal", "Vintage", "Dreamy")
private const val maxChips = 20
private const val maxRuns = 30
private const val parallelRuns = 3

/**
 * Credits charged per row generated (1 chat + 1 image generation). One
 * Generate tap fans out to `parallelRuns × creditPerRun` credits total.
 */
private const val creditPerRun = 1
private const val costPerGenerate = creditPerRun * parallelRuns

/** Groups consecutive runs into 2-second `createdAt` buckets — see [RunBatch]. */
private fun batched(runs: List<Run>): List<RunBatch> {
    val result = mutableListOf<RunBatch>()
    var current = mutableListOf<Run>()
    var currentKey = Long.MIN_VALUE
    val bucketMillis = 2_000L

    for (run in runs) {
        val key = Math.floorDiv(run.createdAt, bucketMillis)
        if (current.isNotEmpty() && key == currentKey) {
            current.add(run)
        } else {
            current.firstOrNull()?.let { first ->
                result.add(RunBatch(id = first.id, createdAt = first.createdAt, runs = current))
            }
            current = mutableListOf(run)
            currentKey = key
        }
    }
    current.firstOrNull()?.let { first ->
        result.add(RunBatch(id = first.id, createdAt = first.createdAt, runs = current))
    }
    return result
}

private fun relativeString(millis: Long): String =
    DateUtils.getRelativeTimeSpanString(
        millis,
        System.currentTimeMillis(),
        0L,
        DateUtils.FORMAT_ABBREV_RELATIVE,
    ).toString()

// MARK: - ContentView

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ContentView(user: String, password: String) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    val scope = rememberCoroutineScope()

    remember(user, password) {
        ImageService.configure(user, password)
        // Rust owns the documents root; point it at filesDir before any
        // ProjectService call. Guarded so tooling previews don't crash on a
        // missing native lib.
        runCatching { ProjectService.initDocuments(context.filesDir.absolutePath) }
        true
    }

    var chips by remember { mutableStateOf(emptyList<Chip>()) }
    var chipsLoaded by remember { mutableStateOf(false) }
    var runs by remember { mutableStateOf(emptyList<Run>()) }
    var editingId by remember { mutableStateOf<String?>(null) }
    var editingText by remember { mutableStateOf("") }
    var newChipText by remember { mutableStateOf("") }
    var addingNew by remember { mutableStateOf(false) }
    var pendingUndos by remember { mutableStateOf(emptyList<PendingUndo>()) }
    /** In-flight generation jobs, keyed by run id. Cancelled when the row is
     *  removed so we don't burn API calls on results no one will see. */
    val inflight = remember { mutableStateMapOf<String, Job>() }
    var showLikedOnly by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        chips = Store.loadChips(context)
        chipsLoaded = true
        runs = runCatching { Store.loadRuns() }.getOrNull() ?: emptyList()
    }
    LaunchedEffect(chips) {
        if (chipsLoaded) Store.saveChips(context, chips)
    }

    // MARK: Actions

    fun atCap(): Boolean = chips.size >= maxChips

    fun tap(type: HapticFeedbackType = HapticFeedbackType.ContextClick) {
        haptics.performHapticFeedback(type)
    }

    fun commitEdit() {
        val id = editingId ?: return
        val trimmed = editingText.trim()
        if (trimmed.isEmpty()) {
            chips = chips.filterNot { it.id == id }
        } else {
            chips = chips.map { if (it.id == id) it.copy(text = trimmed) else it }
        }
        editingId = null
        editingText = ""
    }

    fun commitAdd() {
        if (!addingNew) return
        val trimmed = newChipText.trim()
        if (trimmed.isNotEmpty() && !atCap()) {
            chips = chips + Chip(text = trimmed)
        }
        addingNew = false
        newChipText = ""
    }

    fun dismissAll() {
        commitEdit()
        commitAdd()
        focusManager.clearFocus()
        keyboard?.hide()
    }

    fun beginEdit(chip: Chip) {
        commitEdit()
        commitAdd()
        tap()
        editingId = chip.id
        editingText = chip.text
    }

    fun remove(chip: Chip) {
        tap(HapticFeedbackType.VirtualKey)
        chips = chips.filterNot { it.id == chip.id }
    }

    fun beginAdd() {
        commitEdit()
        tap()
        addingNew = true
        newChipText = ""
    }

    fun commitAndContinueAdd() {
        if (!addingNew) return
        val trimmed = newChipText.trim()
        if (trimmed.isEmpty()) {
            addingNew = false
            newChipText = ""
            focusManager.clearFocus()
            keyboard?.hide()
            return
        }
        if (atCap()) {
            tap(HapticFeedbackType.Reject)
            return
        }
        tap()
        chips = chips + Chip(text = trimmed)
        newChipText = ""
    }

    fun insertPreset(name: String) {
        commitEdit()
        commitAdd()
        if (atCap()) {
            tap(HapticFeedbackType.Reject)
            return
        }
        tap()
        chips = chips + Chip(text = name.lowercase())
    }

    fun clearAll() {
        dismissAll()
        tap(HapticFeedbackType.VirtualKey)
        chips = emptyList()
    }

    /**
     * Live API resolution for a single row. Every Generate goes through chat
     * synthesis first; only the downstream call (Klein vs Flux2Pro) depends on
     * whether CharacterCast is set. Persists bytes via ProjectService with an
     * honest model name. Cancellation (via removeRun) propagates through the
     * coroutine so we don't burn API calls.
     */
    fun resolveReal(runId: String, idea: String) {
        val job = scope.launch {
            try {
                val synthesized = ImageService.chatSynthesize(idea)
                ensureActive()
                val data: ByteArray
                val modelName: String
                val cast = ProjectService.getCharacterCast()
                if (cast != null) {
                    data = ImageService.castGenerate(
                        prompt = synthesized,
                        characterFilename = cast.first,
                        targetFilename = cast.second,
                    ).first
                    modelName = "Flux2KleinI2I"
                } else {
                    data = ImageService.generate(synthesized).first
                    modelName = "Flux2Pro"
                }
                ensureActive()
                val row = runs.firstOrNull { it.id == runId } ?: return@launch
                val bmp = withContext(Dispatchers.IO) {
                    BitmapFactory.decodeByteArray(data, 0, data.size)
                } ?: throw ImageServiceException("couldn't read result")
                val filename = Store.saveRun(data, runId, row.chips, modelName)
                // If the user toggled the heart while we were generating, the
                // in-memory liked flag is already true but the file wasn't
                // created yet — flush it now.
                if (runs.firstOrNull { it.id == runId }?.liked == true) {
                    Store.setLiked(filename, true)
                }
                runs = runs.map {
                    if (it.id == runId) {
                        it.copy(state = RunState.Loaded, imageFilename = filename, image = bmp.asImageBitmap())
                    } else it
                }
                tap(HapticFeedbackType.Confirm)
            } catch (e: CancellationException) {
                // Row was removed before generation finished — nothing to do.
                throw e
            } catch (_: Exception) {
                if (runs.none { it.id == runId }) return@launch
                runs = runs.map { if (it.id == runId) it.copy(state = RunState.Failed) else it }
                tap(HapticFeedbackType.Reject)
            } finally {
                inflight.remove(runId)
            }
        }
        inflight[runId] = job
    }

    /**
     * Trims to [maxRuns], evicting unliked rows from the tail first so the
     * user's keepers survive past the cap.
     */
    fun trimHistory() {
        val current = runs.toMutableList()
        var overflow = current.size - maxRuns
        if (overflow <= 0) return
        val toDelete = mutableListOf<String>()
        var i = current.size - 1
        while (overflow > 0 && i >= 0) {
            if (!current[i].liked) {
                toDelete.add(current.removeAt(i).imageFilename)
                overflow -= 1
            }
            i -= 1
        }
        if (current.size > maxRuns) {
            val oldestExcess = current.size - maxRuns
            current.takeLast(oldestExcess).forEach { toDelete.add(it.imageFilename) }
            repeat(oldestExcess) { current.removeAt(current.size - 1) }
        }
        runs = current
        if (toDelete.isNotEmpty()) {
            scope.launch { toDelete.forEach { Store.deleteImage(it) } }
        }
    }

    /**
     * Fans out [parallelRuns] real synthesizes per Generate tap. Each row
     * appears shimmering, then resolves via the live chat→generate pipeline.
     * Per-row jobs are tracked so removeRun can cancel them.
     */
    fun generate() {
        if (chips.isEmpty()) return
        dismissAll()
        tap()
        val snapshot = chips.map { Chip(text = it.text) }
        val idea = snapshot.joinToString(", ") { it.text }
        val createdAt = System.currentTimeMillis()
        val new = List(parallelRuns) {
            Run(
                chips = snapshot.map { Chip(text = it.text) },
                state = RunState.Loading,
                paletteIndex = Random.nextInt(gradientPalettes.size),
                createdAt = createdAt,
            )
        }
        runs = new + runs
        trimHistory()
        for (run in new) resolveReal(run.id, idea)
    }

    fun retry(run: Run) {
        if (runs.none { it.id == run.id }) return
        tap()
        val idea = run.chips.joinToString(", ") { it.text }
        runs = runs.map { if (it.id == run.id) it.copy(state = RunState.Loading) else it }
        resolveReal(run.id, idea)
    }

    /**
     * Tap a past run to replace the editor with its prompt. Fresh chip IDs
     * avoid collisions with the row that's still rendering the snapshot.
     */
    fun restore(run: Run) {
        dismissAll()
        tap()
        chips = run.chips.map { Chip(text = it.text) }
    }

    fun removeRun(run: Run) {
        val idx = runs.indexOfFirst { it.id == run.id }
        if (idx == -1) return
        tap(HapticFeedbackType.VirtualKey)
        // Cancel any in-flight generation so we don't pay for unwanted bytes.
        inflight.remove(run.id)?.cancel()
        val undo = PendingUndo(run = runs[idx], index = idx)
        runs = runs.filterNot { it.id == run.id }
        pendingUndos = pendingUndos + undo
        scope.launch {
            delay(3_000)
            // If the user didn't undo, delete the disk bytes for real and
            // drop the entry from the undo stack.
            if (pendingUndos.any { it.id == undo.id }) {
                Store.deleteImage(undo.run.imageFilename)
                pendingUndos = pendingUndos.filterNot { it.id == undo.id }
            }
        }
    }

    /** LIFO undo — restores the most recent removal first. */
    fun undoRemove() {
        val undo = pendingUndos.lastOrNull() ?: return
        tap()
        val insertAt = minOf(undo.index, runs.size)
        runs = runs.toMutableList().apply { add(insertAt, undo.run) }
        pendingUndos = pendingUndos.filterNot { it.id == undo.id }
    }

    fun toggleLike(run: Run) {
        val row = runs.firstOrNull { it.id == run.id } ?: return
        tap()
        val liked = !row.liked
        runs = runs.map { if (it.id == run.id) it.copy(liked = liked) else it }
        // Flush to the embedded IPTC rating, but only once the file exists.
        // For still-loading rows, resolveReal mirrors the like at save time.
        if (row.state == RunState.Loaded && row.imageFilename.isNotEmpty()) {
            scope.launch { Store.setLiked(row.imageFilename, liked) }
        }
    }

    fun isActive(run: Run): Boolean =
        run.chips.map { it.text } == chips.map { it.text }

    // MARK: Layout

    val listState = rememberLazyListState()
    // chipFlow is item index 1; the editor counts as visible while any part
    // of it is still on screen — drives the back-to-editor pill.
    val editorVisible by remember { derivedStateOf { listState.firstVisibleItemIndex <= 1 } }

    MaterialTheme(colorScheme = darkColorScheme()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .drawBehind {
                    drawRect(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                Color(red = 0.42f, green = 0.10f, blue = 0.55f).copy(alpha = 0.35f),
                                Color.Transparent,
                            ),
                            center = Offset(size.width * 0.18f, size.height * 0.05f),
                            radius = 420.dp.toPx(),
                        ),
                    )
                    drawRect(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                Color(red = 0.95f, green = 0.30f, blue = 0.55f).copy(alpha = 0.22f),
                                Color.Transparent,
                            ),
                            center = Offset(size.width * 0.92f, size.height * 0.08f),
                            radius = 320.dp.toPx(),
                        ),
                    )
                },
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing),
            ) {
                Header()

                Box(modifier = Modifier.weight(1f)) {
                    val filtered = if (showLikedOnly) runs.filter { it.liked } else runs
                    val batches = batched(filtered)

                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 16.dp),
                    ) {
                        item(key = "editorTop") {
                            PromptHeader(showClear = chips.isNotEmpty(), onClear = { clearAll() })
                        }
                        item(key = "chipFlow") {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 20.dp)
                                    .padding(horizontal = 16.dp)
                                    .animateContentSize(),
                            ) {
                                FlowRow(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    for (chip in chips) {
                                        key(chip.id) {
                                            if (editingId == chip.id) {
                                                InlineChipEditor(
                                                    text = editingText,
                                                    onTextChange = { editingText = it },
                                                    onSubmit = { commitEdit() },
                                                )
                                            } else {
                                                ChipView(
                                                    chip = chip,
                                                    onEdit = { beginEdit(chip) },
                                                    onRemove = { remove(chip) },
                                                )
                                            }
                                        }
                                    }
                                    if (!(atCap() && !addingNew)) {
                                        if (addingNew) {
                                            AddChipField(
                                                text = newChipText,
                                                onTextChange = { newChipText = it },
                                                onSubmit = { commitAndContinueAdd() },
                                            )
                                        } else {
                                            AddChipButton(onClick = { beginAdd() })
                                        }
                                    }
                                }
                                if (chips.isEmpty() && !addingNew) {
                                    Text(
                                        text = "tap + to begin engineering your prompt",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = Color.White.copy(alpha = 0.35f),
                                        modifier = Modifier.padding(top = 10.dp),
                                    )
                                }
                            }
                        }
                        item(key = "presetsLabel") {
                            SectionLabel("PRESETS", modifier = Modifier.padding(top = 20.dp))
                        }
                        item(key = "presetRail") {
                            PresetRail(
                                modifier = Modifier.padding(top = 20.dp),
                                onInsert = { insertPreset(it) },
                            )
                        }
                        if (runs.isNotEmpty()) {
                            item(key = "resultsHeader") {
                                ResultsHeader(
                                    modifier = Modifier.padding(top = 20.dp),
                                    showFilter = runs.any { it.liked },
                                    showLikedOnly = showLikedOnly,
                                    onToggleFilter = {
                                        tap()
                                        showLikedOnly = !showLikedOnly
                                    },
                                )
                            }
                            for ((batchIndex, batch) in batches.withIndex()) {
                                item(key = "batchHeader-${batch.id}") {
                                    BatchHeader(
                                        createdAt = batch.createdAt,
                                        modifier = Modifier
                                            .animateItem()
                                            .padding(top = if (batchIndex == 0) 20.dp else 16.dp),
                                    )
                                }
                                items(batch.runs, key = { "run-${it.id}" }) { run ->
                                    ResultRow(
                                        run = run,
                                        active = isActive(run),
                                        modifier = Modifier
                                            .animateItem()
                                            .padding(top = 10.dp),
                                        onRestore = { restore(run) },
                                        onToggleLike = { toggleLike(run) },
                                        onRetry = { retry(run) },
                                        onRemove = { removeRun(run) },
                                    )
                                }
                            }
                        }
                    }

                    // Floating status reader shown when the editor has scrolled
                    // out of view. (Fully qualified: inside Box-in-Column the
                    // ColumnScope.AnimatedVisibility overload would otherwise
                    // win resolution and fail on the implicit receiver.)
                    androidx.compose.animation.AnimatedVisibility(
                        visible = !editorVisible && chips.isNotEmpty(),
                        modifier = Modifier
                            .align(Alignment.TopCenter)
                            .padding(top = 8.dp),
                        enter = slideInVertically { -it } + fadeIn(),
                        exit = slideOutVertically { -it } + fadeOut(),
                    ) {
                        BackToEditorPill(
                            promptText = chips.joinToString(" · ") { it.text },
                            onClick = {
                                tap()
                                scope.launch { listState.animateScrollToItem(0) }
                            },
                        )
                    }
                }

                GenerateButton(
                    enabled = chips.isNotEmpty(),
                    onClick = { generate() },
                    modifier = Modifier.padding(start = 22.dp, end = 22.dp, bottom = 14.dp),
                )
            }

            // Transient toast for undoing the last row removal. Auto-dismisses
            // after 3 seconds — long enough to catch a mistake, short enough
            // not to clutter the screen.
            AnimatedVisibility(
                visible = pendingUndos.isNotEmpty(),
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(horizontal = 22.dp)
                    .padding(bottom = 88.dp),
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut(),
            ) {
                UndoToast(count = pendingUndos.size, onUndo = { undoRemove() })
            }
        }
    }
}

// MARK: Header

@Composable
private fun Header() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 22.dp, end = 22.dp, top = 8.dp, bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(Brush.horizontalGradient(listOf(Purple, Pink))),
        )
        Text(
            text = "ENGINEER",
            fontSize = 12.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 2.8.sp,
            color = Color.White.copy(alpha = 0.85f),
        )
    }
}

/**
 * Displays the live joined prompt (truncated) so the user can confirm restores
 * from history without scrolling, and tap to spring back to the editor.
 */
@Composable
private fun BackToEditorPill(promptText: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .padding(horizontal = 22.dp)
            .widthIn(max = 320.dp)
            .shadow(
                elevation = 12.dp,
                shape = CircleShape,
                ambientColor = PinkGlow.copy(alpha = 0.35f),
                spotColor = PinkGlow.copy(alpha = 0.35f),
            )
            .clip(CircleShape)
            .background(
                Brush.horizontalGradient(
                    listOf(Purple.copy(alpha = 0.92f), Pink.copy(alpha = 0.92f)),
                ),
            )
            .border(0.7.dp, Color.White.copy(alpha = 0.3f), CircleShape)
            .clickable(onClickLabel = "Scroll back to editor. Current prompt: $promptText") { onClick() }
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = promptText,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Icon(
            imageVector = Icons.Filled.KeyboardArrowUp,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.85f),
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
private fun UndoToast(count: Int, onUndo: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(16.dp, RoundedCornerShape(14.dp))
            .clip(RoundedCornerShape(14.dp))
            .background(Color.Black.copy(alpha = 0.7f))
            .border(0.5.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Delete,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.7f),
            modifier = Modifier.size(14.dp),
        )
        Text(
            text = if (count > 1) "$count results removed" else "Result removed",
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White,
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = "Undo",
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = Pink,
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .clickable(onClickLabel = "Undo remove") { onUndo() }
                .padding(horizontal = 10.dp, vertical = 6.dp),
        )
    }
}

/** PROMPT section header with an inline CLEAR affordance on the right. */
@Composable
private fun PromptHeader(showClear: Boolean, onClear: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionLabel("PROMPT")
        Spacer(modifier = Modifier.weight(1f))
        if (showClear) {
            Text(
                text = "CLEAR",
                fontSize = 10.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = 1.5.sp,
                color = Color.White.copy(alpha = 0.5f),
                modifier = Modifier
                    .padding(end = 22.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.05f))
                    .border(0.5.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .clickable(onClickLabel = "Clear all phrases") { onClear() }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
private fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        fontSize = 10.sp,
        fontWeight = FontWeight.ExtraBold,
        letterSpacing = 2.sp,
        color = Color.White.copy(alpha = 0.45f),
        modifier = modifier.padding(horizontal = 22.dp),
    )
}

// MARK: Chip flow

@Composable
private fun ChipView(chip: Chip, onEdit: () -> Unit, onRemove: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(0.5.dp, Color.White.copy(alpha = 0.12f), CircleShape)
            .padding(start = 14.dp, end = 5.dp, top = 7.dp, bottom = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = chip.text,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.92f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .widthIn(max = 300.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClickLabel = "Edit ${chip.text}",
                ) { onEdit() },
        )
        CircleIconButton(
            icon = Icons.Filled.Close,
            contentDescription = "Remove ${chip.text}",
            tint = Color.White.copy(alpha = 0.6f),
            background = Color.White.copy(alpha = 0.10f),
            size = 22.dp,
            iconSize = 11.dp,
            onClick = onRemove,
        )
    }
}

@Composable
private fun InlineChipEditor(
    text: String,
    onTextChange: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.14f))
            .border(0.7.dp, Color.White.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    ) {
        AutoChipField(
            text = text,
            onTextChange = onTextChange,
            placeholder = "",
            maxWidth = 240.dp,
            imeAction = ImeAction.Done,
            onSubmit = onSubmit,
        )
    }
}

@Composable
private fun AddChipField(
    text: String,
    onTextChange: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.14f))
            .border(0.7.dp, Color.White.copy(alpha = 0.35f), CircleShape)
            .padding(horizontal = 14.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.6f),
            modifier = Modifier.size(12.dp),
        )
        AutoChipField(
            text = text,
            onTextChange = onTextChange,
            placeholder = "phrase",
            maxWidth = 240.dp,
            imeAction = ImeAction.Next,
            onSubmit = onSubmit,
        )
    }
}

@Composable
private fun AddChipButton(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.04f))
            .drawBehind {
                drawRoundRect(
                    color = Color.White.copy(alpha = 0.18f),
                    cornerRadius = CornerRadius(size.height / 2f),
                    style = Stroke(
                        width = 0.7.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(
                            floatArrayOf(3.dp.toPx(), 4.dp.toPx()),
                            0f,
                        ),
                    ),
                )
            }
            .clickable(onClickLabel = "Add phrase") { onClick() }
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.55f),
            modifier = Modifier.size(12.dp),
        )
        Text(
            text = "add",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.55f),
        )
    }
}

// MARK: Preset rail

@Composable
private fun PresetRail(modifier: Modifier = Modifier, onInsert: (String) -> Unit) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 22.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            for (preset in presets) {
                Text(
                    text = preset,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.06f))
                        .border(0.5.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                        .clickable { onInsert(preset) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
        }
    }
}

// MARK: Results

/**
 * RESULTS row with the LIKED filter chip on the right. Filter is hidden when
 * no liked rows exist (nothing to surface, no point in the affordance).
 */
@Composable
private fun ResultsHeader(
    modifier: Modifier = Modifier,
    showFilter: Boolean,
    showLikedOnly: Boolean,
    onToggleFilter: () -> Unit,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionLabel("RESULTS")
        Spacer(modifier = Modifier.weight(1f))
        if (showFilter) {
            Row(
                modifier = Modifier
                    .padding(end = 22.dp)
                    .clip(CircleShape)
                    .background(
                        if (showLikedOnly) Pink.copy(alpha = 0.15f)
                        else Color.White.copy(alpha = 0.05f),
                    )
                    .border(
                        0.5.dp,
                        if (showLikedOnly) Pink.copy(alpha = 0.5f)
                        else Color.White.copy(alpha = 0.12f),
                        CircleShape,
                    )
                    .clickable(
                        onClickLabel = if (showLikedOnly) "Show all results" else "Show only liked results",
                    ) { onToggleFilter() }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = if (showLikedOnly) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = null,
                    tint = if (showLikedOnly) Pink else Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.size(11.dp),
                )
                Text(
                    text = "LIKED",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.ExtraBold,
                    letterSpacing = 1.5.sp,
                    color = if (showLikedOnly) Pink else Color.White.copy(alpha = 0.5f),
                )
            }
        }
    }
}

/**
 * "GENERATED · 2m ago" caption above each batch of rows. Snapshot at render
 * time — the relative string ages with each re-render, which is good enough
 * for human time perception without a 1s timer.
 */
@Composable
private fun BatchHeader(createdAt: Long, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.padding(horizontal = 22.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "GENERATED",
            fontSize = 9.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 1.2.sp,
            color = Color.White.copy(alpha = 0.4f),
        )
        Text(
            text = "·",
            fontSize = 9.sp,
            fontWeight = FontWeight.ExtraBold,
            color = Color.White.copy(alpha = 0.4f),
        )
        Text(
            text = relativeString(createdAt),
            fontSize = 9.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = 0.8.sp,
            color = Color.White.copy(alpha = 0.4f),
        )
    }
}

@Composable
private fun ResultRow(
    run: Run,
    active: Boolean,
    modifier: Modifier = Modifier,
    onRestore: () -> Unit,
    onToggleLike: () -> Unit,
    onRetry: () -> Unit,
    onRemove: () -> Unit,
) {
    val shape = RoundedCornerShape(16.dp)
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.985f else 1f,
        animationSpec = tween(120),
        label = "rowScale",
    )
    val pressAlpha by animateFloatAsState(
        targetValue = if (pressed) 0.92f else 1f,
        animationSpec = tween(120),
        label = "rowAlpha",
    )
    val joinedPrompt = run.chips.joinToString(" · ") { it.text }

    Row(
        modifier = modifier
            .padding(horizontal = 22.dp)
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                alpha = pressAlpha
            }
            .clip(shape)
            .background(Color.White.copy(alpha = if (active) 0.08f else 0.04f))
            .then(
                if (active) {
                    Modifier.border(1.2.dp, Brush.horizontalGradient(listOf(Purple, Pink)), shape)
                } else {
                    Modifier.border(0.5.dp, Color.White.copy(alpha = 0.08f), shape)
                },
            )
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClickLabel = "Restore prompt: ${run.chips.joinToString(", ") { it.text }}",
            ) { onRestore() }
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Thumbnail(run)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = joinedPrompt,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.82f),
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = "${run.chips.size} ${if (run.chips.size == 1) "phrase" else "phrases"}",
                fontSize = 9.sp,
                fontWeight = FontWeight.ExtraBold,
                letterSpacing = 1.2.sp,
                color = Color.White.copy(alpha = 0.4f),
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (run.state == RunState.Failed) {
                CircleIconButton(
                    icon = Icons.Filled.Refresh,
                    contentDescription = "Retry generation",
                    tint = Color.White.copy(alpha = 0.8f),
                    background = Color.White.copy(alpha = 0.10f),
                    size = 28.dp,
                    iconSize = 14.dp,
                    onClick = onRetry,
                )
            } else {
                CircleIconButton(
                    icon = if (run.liked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (run.liked) "Unlike result" else "Like result",
                    tint = if (run.liked) Pink else Color.White.copy(alpha = 0.55f),
                    background = Color.White.copy(alpha = 0.06f),
                    size = 28.dp,
                    iconSize = 15.dp,
                    onClick = onToggleLike,
                )
            }
            CircleIconButton(
                icon = Icons.Filled.Close,
                contentDescription = "Remove result",
                tint = Color.White.copy(alpha = 0.5f),
                background = Color.White.copy(alpha = 0.06f),
                size = 28.dp,
                iconSize = 12.dp,
                onClick = onRemove,
            )
        }
    }
}

@Composable
private fun CircleIconButton(
    icon: ImageVector,
    contentDescription: String,
    tint: Color,
    background: Color,
    size: Dp,
    iconSize: Dp,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(background)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(iconSize),
        )
    }
}

@Composable
private fun Thumbnail(run: Run) {
    val palette = gradientPalettes[run.paletteIndex % gradientPalettes.size]
    Box(
        modifier = Modifier
            .size(96.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Brush.linearGradient(palette)),
        contentAlignment = Alignment.Center,
    ) {
        when (run.state) {
            RunState.Loading -> ShimmerOverlay(modifier = Modifier.fillMaxSize())
            RunState.Loaded -> run.image?.let { img ->
                Image(
                    bitmap = img,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            RunState.Failed -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.45f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.9f),
                    modifier = Modifier.size(24.dp),
                )
            }
        }
    }
}

// MARK: Generate

@Composable
private fun GenerateButton(
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(20.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(58.dp)
            .alpha(if (enabled) 1f else 0.5f)
            .shadow(
                elevation = 24.dp,
                shape = shape,
                ambientColor = PinkGlow.copy(alpha = 0.45f),
                spotColor = PinkGlow.copy(alpha = 0.45f),
            )
            .clip(shape)
            .background(Brush.horizontalGradient(listOf(Purple, Pink)))
            .background(
                Brush.verticalGradient(
                    0f to Color.White.copy(alpha = 0.175f),
                    0.5f to Color.Transparent,
                ),
            )
            .border(0.7.dp, Color.White.copy(alpha = 0.5f), shape)
            .clickable(enabled = enabled) { onClick() },
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = SparklesIcon,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(20.dp),
        )
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            Text(
                text = "Generate",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.5.sp,
                color = Color.White,
            )
            Text(
                text = "$costPerGenerate credits",
                fontSize = 9.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.4.sp,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
    }
}

// MARK: - AutoChipField

/**
 * A text field that grows with its content — measures the current text with a
 * TextMeasurer and sizes itself to min(max(60, width + 4), maxWidth), the same
 * mirror-measurement trick as the SwiftUI original.
 */
@Composable
private fun AutoChipField(
    text: String,
    onTextChange: (String) -> Unit,
    placeholder: String,
    maxWidth: Dp,
    imeAction: ImeAction,
    onSubmit: () -> Unit,
) {
    val textStyle = TextStyle(
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        color = Color.White,
    )
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val measuredWidth = remember(text, placeholder) {
        val widthPx = measurer.measure(
            text = AnnotatedString(text.ifEmpty { placeholder }),
            style = textStyle,
            maxLines = 1,
        ).size.width
        with(density) { widthPx.toDp() }
    }
    val fieldWidth = (measuredWidth + 4.dp).coerceIn(60.dp, maxWidth)
    val focusRequester = remember { FocusRequester() }

    BasicTextField(
        value = text,
        onValueChange = onTextChange,
        textStyle = textStyle,
        cursorBrush = SolidColor(Color.White),
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = imeAction),
        keyboardActions = KeyboardActions(
            onDone = { onSubmit() },
            onNext = { onSubmit() },
        ),
        modifier = Modifier
            .width(fieldWidth)
            .focusRequester(focusRequester),
        decorationBox = { innerTextField ->
            Box(contentAlignment = Alignment.CenterStart) {
                if (text.isEmpty() && placeholder.isNotEmpty()) {
                    Text(
                        text = placeholder,
                        style = textStyle.copy(color = Color.White.copy(alpha = 0.35f)),
                        maxLines = 1,
                    )
                }
                innerTextField()
            }
        },
    )

    LaunchedEffect(Unit) { focusRequester.requestFocus() }
}

// MARK: - Shimmer

@Composable
private fun ShimmerOverlay(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val phase by transition.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_200, easing = LinearEasing)),
        label = "shimmerPhase",
    )
    Box(
        modifier = modifier.drawBehind {
            val bandWidth = size.width * 0.6f
            val start = phase * size.width * 1.6f
            drawRect(
                brush = Brush.horizontalGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0f),
                        Color.White.copy(alpha = 0.35f),
                        Color.White.copy(alpha = 0f),
                    ),
                    startX = start,
                    endX = start + bandWidth,
                ),
                blendMode = BlendMode.Plus,
            )
        },
    )
}

// MARK: - Icons

/** Material "auto awesome" sparkles — inlined so we don't pull icons-extended. */
private val SparklesIcon: ImageVector = materialIcon(name = "Filled.Sparkles") {
    materialPath {
        moveTo(19.0f, 9.0f)
        lineToRelative(1.25f, -2.75f)
        lineTo(23.0f, 5.0f)
        lineToRelative(-2.75f, -1.25f)
        lineTo(19.0f, 1.0f)
        lineToRelative(-1.25f, 2.75f)
        lineTo(15.0f, 5.0f)
        lineToRelative(2.75f, 1.25f)
        close()
        moveTo(11.5f, 9.5f)
        lineTo(9.0f, 4.0f)
        lineTo(6.5f, 9.5f)
        lineTo(1.0f, 12.0f)
        lineToRelative(5.5f, 2.5f)
        lineTo(9.0f, 20.0f)
        lineToRelative(2.5f, -5.5f)
        lineTo(17.0f, 12.0f)
        close()
        moveTo(19.0f, 15.0f)
        lineToRelative(-1.25f, 2.75f)
        lineTo(15.0f, 19.0f)
        lineToRelative(2.75f, 1.25f)
        lineTo(19.0f, 23.0f)
        lineToRelative(1.25f, -2.75f)
        lineTo(23.0f, 19.0f)
        lineToRelative(-2.75f, -1.25f)
        close()
    }
}

@Preview
@Composable
private fun ContentViewPreview() {
    ContentView(user = "019ec07a-c943-7275-b758-2315b8c9fa6f", password = "")
}
