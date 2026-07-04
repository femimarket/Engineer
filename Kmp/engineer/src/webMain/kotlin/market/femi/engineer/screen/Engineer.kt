@file:OptIn(
    ExperimentalUuidApi::class,
    ExperimentalEncodingApi::class,
    ExperimentalLayoutApi::class,
)

package market.femi.engineer.screen

// Engineer screen — chip-list prompt builder + result history. Verbatim port of
// ImageIterate2/Prod/ContentView.swift. Real backend (chat synthesize → generate)
// and disk-backed persistence so runs and chips survive launches. Source of truth
// is OPFS via ProjectService; each row is one PNG under <runId>.png with chips as
// XMP subject keywords, the joined prompt as caption, model as software, like as
// rating. The editor's working chip set lives in localStorage (typing in progress,
// not a generation). Black + purple→pink radial glow, mirroring the Swift Theme.

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.browser.localStorage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import market.femi.api.decodeImageBitmap
import market.femi.api.deleteFile
import market.femi.api.jsDateNow
import market.femi.api.readFileBytes
import market.femi.api.readFileMtime
import market.femi.api.toByteArray
import market.femi.api.ChatMessage
import market.femi.api.ProjectService
import market.femi.api.Role
import market.femi.api.flux2KleinI2I
import market.femi.api.flux2Pro
import market.femi.api.qwen3_6_35b_a3b
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.math.abs
import kotlin.math.floor
import kotlin.random.Random
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

// MARK: - Palette (purple → pink family)

private val Purple = Color(0.55f, 0.20f, 1.0f)
private val Pink = Color(1.0f, 0.30f, 0.65f)

// MARK: - Models

private data class Chip(val id: Uuid = Uuid.random(), val text: String)

private enum class RunState { Loading, Loaded, Failed }

private data class Run(
    val id: Uuid = Uuid.random(),
    val chips: List<Chip>,
    val state: RunState,
    /// OPFS filename. Empty until loaded.
    val imageFilename: String = "",
    /// Decoded image, cached after first read. Null while loading or failed.
    val image: ImageBitmap? = null,
    val liked: Boolean = false,
    /// Index into `gradientPalettes` — shimmer/failure backdrop + decode fallback.
    val paletteIndex: Int,
    /// Millis since epoch. Honest creation time; on reload it's the file mtime.
    val createdAt: Double,
)

/// One batch as rendered in RESULTS. Grouping derives from `Run.createdAt`
/// (2-second window) — runs from one Generate tap share a bucket.
private data class RunBatch(val id: Uuid, val createdAt: Double, val runs: List<Run>)

private data class PendingUndo(val id: Uuid = Uuid.random(), val run: Run, val index: Int)

// MARK: - Persistence

@Serializable
private data class ChipDTO(val id: String, val text: String)

/// Disk (OPFS) is the source of truth for runs; localStorage holds the working chip set.
private object EngineerStore {
    private const val chipsKey = "engineerChips.v1"
    private val json = Json { ignoreUnknownKeys = true }

    fun loadChips(): List<Chip> = runCatching {
        val raw = localStorage.getItem(chipsKey) ?: return emptyList()
        json.decodeFromString<List<ChipDTO>>(raw).map {
            Chip(runCatching { Uuid.parse(it.id) }.getOrElse { Uuid.random() }, it.text)
        }
    }.getOrDefault(emptyList())

    fun saveChips(chips: List<Chip>) {
        runCatching {
            localStorage.setItem(chipsKey, json.encodeToString(chips.map { ChipDTO(it.id.toString(), it.text) }))
        }
    }

    /// Walk OPFS via ProjectService and reconstruct Runs from each PNG's embedded
    /// XMP (subject → chips, rating → liked) plus the file mtime. Newest first.
    /// Metadata-only: image bytes are NOT read here. A disk row is a finished
    /// generation, so it's born Loaded with image = null; the visible row reads +
    /// decodes its own file (see the LazyColumn item). Eagerly decoding every PNG
    /// here is what hung the screen when OPFS held many files.
    suspend fun loadRuns(): List<Run> {
        val out = mutableListOf<Run>()
        for (filename in ProjectService.getAllGenerations()) {
            if (!filename.lowercase().endsWith(".png")) continue
            val chipTexts = ProjectService.getSubject(filename) ?: emptyList()
            val liked = ProjectService.getLike(filename)
            val createdAt = readFileMtime(filename)
            val runId = runCatching { Uuid.parse(filename.substringBeforeLast('.')) }.getOrElse { Uuid.random() }
            out.add(
                Run(
                    id = runId,
                    chips = chipTexts.map { Chip(text = it) },
                    state = RunState.Loaded,
                    imageFilename = filename,
                    image = null,
                    liked = liked,
                    paletteIndex = abs(filename.hashCode()),
                    createdAt = createdAt,
                ),
            )
        }
        return out.sortedByDescending { it.createdAt }
    }

    /// Persist bytes with chips as XMP subject, joined prompt as caption, model as software.
    /// `model` is honest: "Flux2Pro" default, "Flux2KleinI2I" in cast mode. Returns the filename.
    suspend fun saveRun(data: ByteArray, runId: Uuid, chips: List<Chip>, model: String = "Flux2Pro"): String {
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

    suspend fun deleteImage(filename: String) {
        if (filename.isEmpty()) return
        runCatching { deleteFile(filename) }
    }
}

// MARK: - Image service (real backend)

/// New Api shape: direct suspend functions, Rust FFI under the hood. Each returns
/// bytes directly; on lib-level failure the bytes are a sentinel PNG that still
/// decodes, so failure only surfaces if decode fails downstream.
private class ImageService(val user: String, val password: String) {

    /// Cast mode: pass both reference files as base64 and let the FFI handle it.
    suspend fun castGenerate(prompt: String, characterFilename: String, targetFilename: String): ByteArray {
        val characterData = readFileBytes(characterFilename).toByteArray()
        val targetData = readFileBytes(targetFilename).toByteArray()
        return flux2KleinI2I(
            user = user,
            pass = password,
            imageB64 = Base64.encode(characterData),
            image2B64 = Base64.encode(targetData),
            prompt = prompt,
        )
    }

    /// Chat synthesis via Qwen. Runs on every Generate. Returns the last assistant
    /// message; falls back to the original idea if the model returned nothing.
    suspend fun chatSynthesize(idea: String): String {
        val userIdea = idea.ifEmpty { "Surprise me — generate something interesting." }
        val synthesizerRequest =
            "Make image prompt frame for Flux2. Reply with only the prompt, nothing else.\nIdea: $userIdea"
        val messages = qwen3_6_35b_a3b(
            user = user,
            pass = password,
            messages = listOf(ChatMessage(Role.User, synthesizerRequest)),
        )
        val last = messages.lastOrNull { it.role == Role.Assistant }?.content
        return if (!last.isNullOrEmpty()) last else userIdea
    }

    /// Default text-to-image via Flux2Pro. Caller supplies a pre-synthesized prompt.
    suspend fun generate(prompt: String): ByteArray = flux2Pro(user = user, pass = password, prompt = prompt)
}

// MARK: - Engineer (the screen)

@Composable
fun Engineer(user: String, password: String, onOpen: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    val imageService = remember(user, password) { ImageService(user, password) }

    val chips = remember { mutableStateListOf<Chip>().apply { addAll(EngineerStore.loadChips()) } }
    val runs = remember { mutableStateListOf<Run>() }
    var editingId by remember { mutableStateOf<Uuid?>(null) }
    var editingText by remember { mutableStateOf("") }
    var newChipText by remember { mutableStateOf("") }
    var addingNew by remember { mutableStateOf(false) }
    var showLikedOnly by remember { mutableStateOf(false) }
    val pendingUndos = remember { mutableStateListOf<PendingUndo>() }
    // In-flight generation Jobs, keyed by run id. Cancelled when a row is removed.
    val inflight = remember { mutableMapOf<Uuid, Job>() }

    val maxChips = 20
    val maxRuns = 30
    val parallelRuns = 3
    val creditPerRun = 1
    val costPerGenerate = creditPerRun * parallelRuns
    fun atCap() = chips.size >= maxChips

    // Focus lives on whichever field is active (add or edit). One requester serves both.
    val fieldFocus = remember { FocusRequester() }

    // Persist the working chip set whenever it changes (Swift .onChange(of: chips)).
    // Key on a lossless id+text signature so no distinct chip set collides (e.g. one
    // chip "a b" vs two chips "a","b" must not flatten to the same key and skip a save).
    val chipsSignature = chips.joinToString("") { "${it.id}${it.text}" }
    LaunchedEffect(chipsSignature) { EngineerStore.saveChips(chips.toList()) }

    // Reconstruct history from disk once.
    LaunchedEffect(Unit) {
        val loaded = EngineerStore.loadRuns()
        if (loaded.isNotEmpty()) {
            runs.clear()
            runs.addAll(loaded)
        }
    }

    // ---- helpers reading current state ----
    fun isActive(run: Run) = run.chips.map { it.text } == chips.map { it.text }
    fun joinedPrompt(run: Run) = run.chips.joinToString(" · ") { it.text }

    // ---- editor actions ----
    fun commitEdit() {
        val id = editingId ?: return
        val trimmed = editingText.trim()
        if (trimmed.isEmpty()) {
            chips.removeAll { it.id == id }
        } else {
            val idx = chips.indexOfFirst { it.id == id }
            if (idx >= 0) chips[idx] = chips[idx].copy(text = trimmed)
        }
        editingId = null
        editingText = ""
    }

    fun commitAdd() {
        if (!addingNew) return
        val trimmed = newChipText.trim()
        if (trimmed.isNotEmpty() && !atCap()) chips.add(Chip(text = trimmed))
        addingNew = false
        newChipText = ""
    }

    fun dismissAll() {
        commitEdit()
        commitAdd()
    }

    fun beginEdit(chip: Chip) {
        commitEdit()
        commitAdd()
        editingId = chip.id
        editingText = chip.text
    }

    fun beginAdd() {
        commitEdit()
        addingNew = true
        newChipText = ""
    }

    fun commitAndContinueAdd() {
        if (!addingNew) return
        val trimmed = newChipText.trim()
        if (trimmed.isEmpty()) {
            addingNew = false
            newChipText = ""
            return
        }
        if (atCap()) return
        chips.add(Chip(text = trimmed))
        newChipText = ""
    }

    fun remove(chip: Chip) { chips.removeAll { it.id == chip.id } }

    fun insertPreset(name: String) {
        commitEdit()
        commitAdd()
        if (atCap()) return
        chips.add(Chip(text = name.lowercase()))
    }

    fun clearAll() {
        dismissAll()
        chips.clear()
    }

    fun restore(run: Run) {
        dismissAll()
        chips.clear()
        chips.addAll(run.chips.map { Chip(text = it.text) })
    }

    // ---- history maintenance ----
    fun trimHistory() {
        var overflow = runs.size - maxRuns
        if (overflow <= 0) return
        var i = runs.size - 1
        while (overflow > 0 && i >= 0) {
            if (!runs[i].liked) {
                val dropped = runs.removeAt(i)
                scope.launch { EngineerStore.deleteImage(dropped.imageFilename) }
                overflow -= 1
            }
            i -= 1
        }
        if (runs.size > maxRuns) {
            val oldestExcess = runs.size - maxRuns
            repeat(oldestExcess) {
                val dropped = runs.removeAt(runs.size - 1)
                scope.launch { EngineerStore.deleteImage(dropped.imageFilename) }
            }
        }
    }

    // ---- live resolution ----
    fun resolveReal(runId: Uuid, idea: String) {
        val job = scope.launch {
            try {
                val synthesized = imageService.chatSynthesize(idea)
                val cast = ProjectService.getCharacterCast()
                val data: ByteArray
                val modelName: String
                if (cast != null) {
                    data = imageService.castGenerate(synthesized, cast.first, cast.second)
                    modelName = "Flux2KleinI2I"
                } else {
                    data = imageService.generate(synthesized)
                    modelName = "Flux2Pro"
                }
                val img = decodeImageBitmap(data) ?: throw IllegalStateException("decode failed")
                // A run's chips are an immutable snapshot; read them by id (indices may
                // have shifted while the chat/generate calls were suspended).
                val chipsForSave = runs.firstOrNull { it.id == runId }?.chips ?: return@launch
                val filename = EngineerStore.saveRun(data, runId, chipsForSave, modelName)
                // If the user hearted the row mid-flight, flush the like now.
                if (runs.firstOrNull { it.id == runId }?.liked == true) EngineerStore.setLiked(filename, true)
                // Re-resolve the index AFTER every suspension — a concurrent Generate,
                // removeRun, or trimHistory could have reordered/shrunk the list. Swift's
                // Store.saveRun was synchronous, so this window didn't exist there.
                val idx = runs.indexOfFirst { it.id == runId }
                if (idx >= 0) runs[idx] = runs[idx].copy(state = RunState.Loaded, imageFilename = filename, image = img)
            } catch (c: CancellationException) {
                throw c // row removed before finishing — nothing to do
            } catch (e: Throwable) {
                val idx = runs.indexOfFirst { it.id == runId }
                if (idx >= 0) runs[idx] = runs[idx].copy(state = RunState.Failed)
            } finally {
                inflight.remove(runId)
            }
        }
        inflight[runId] = job
    }

    fun generate() {
        if (chips.isEmpty()) return
        dismissAll()
        val snapshot = chips.map { Chip(text = it.text) }
        val idea = snapshot.joinToString(", ") { it.text }
        val createdAt = jsDateNow()
        val fresh = (0 until parallelRuns).map {
            Run(
                chips = snapshot.map { c -> Chip(text = c.text) },
                state = RunState.Loading,
                paletteIndex = Random.nextInt(gradientPalettes.size),
                createdAt = createdAt,
            )
        }
        runs.addAll(0, fresh)
        trimHistory()
        fresh.forEach { resolveReal(it.id, idea) }
    }

    fun retry(run: Run) {
        val idx = runs.indexOfFirst { it.id == run.id }
        if (idx < 0) return
        val idea = run.chips.joinToString(", ") { it.text }
        runs[idx] = runs[idx].copy(state = RunState.Loading)
        resolveReal(run.id, idea)
    }

    fun toggleLike(run: Run) {
        val idx = runs.indexOfFirst { it.id == run.id }
        if (idx < 0) return
        val nowLiked = !runs[idx].liked
        runs[idx] = runs[idx].copy(liked = nowLiked)
        // Flush to the embedded rating, but only once the file exists.
        if (runs[idx].state == RunState.Loaded && runs[idx].imageFilename.isNotEmpty()) {
            scope.launch { EngineerStore.setLiked(runs[idx].imageFilename, nowLiked) }
        }
    }

    fun undoRemove() {
        val undo = pendingUndos.lastOrNull() ?: return
        val insertAt = minOf(undo.index, runs.size)
        runs.add(insertAt, undo.run)
        pendingUndos.removeAll { it.id == undo.id }
    }

    fun removeRun(run: Run) {
        val idx = runs.indexOfFirst { it.id == run.id }
        if (idx < 0) return
        inflight[run.id]?.cancel()
        inflight.remove(run.id)
        val undo = PendingUndo(run = runs[idx], index = idx)
        runs.removeAt(idx)
        pendingUndos.add(undo)
        scope.launch {
            delay(3000)
            if (pendingUndos.any { it.id == undo.id }) {
                EngineerStore.deleteImage(undo.run.imageFilename)
                pendingUndos.removeAll { it.id == undo.id }
            }
        }
    }

    // ---- layout ----
    val listState = rememberLazyListState()
    // Editor is "visible" while the chip flow (item index 1) is still on screen.
    val editorVisible by remember { derivedStateOf { listState.firstVisibleItemIndex <= 1 } }

    CompositionLocalProvider(LocalBrandFont provides brandFamily()) {
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            // Two radial glows, matching the Swift RadialGradients.
            Box(
                Modifier.fillMaxSize().background(
                    Brush.radialGradient(
                        colors = listOf(Color(0.42f, 0.10f, 0.55f).copy(alpha = 0.35f), Color.Transparent),
                        center = Offset(0.18f * 1400f, 0.05f * 1400f),
                        radius = 460f,
                    ),
                ),
            )
            Box(
                Modifier.fillMaxSize().background(
                    Brush.radialGradient(
                        colors = listOf(Color(0.95f, 0.30f, 0.55f).copy(alpha = 0.22f), Color.Transparent),
                        center = Offset(0.92f * 1400f, 0.08f * 1400f),
                        radius = 360f,
                    ),
                ),
            )

            Column(
                modifier = Modifier
                    .safeContentPadding()
                    .imePadding()
                    .widthIn(max = 620.dp)
                    .fillMaxSize()
                    .align(Alignment.TopCenter),
            ) {
                Header()

                Box(Modifier.weight(1f).fillMaxWidth()) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                        contentPadding = PaddingValues(vertical = 16.dp),
                    ) {
                        item { PromptHeader(hasChips = chips.isNotEmpty(), onClear = { clearAll() }) }
                        item {
                            ChipFlow(
                                chips = chips.toList(),
                                editingId = editingId,
                                editingText = editingText,
                                onEditingTextChange = { editingText = it },
                                addingNew = addingNew,
                                newChipText = newChipText,
                                onNewChipTextChange = { newChipText = it },
                                atCap = atCap(),
                                fieldFocus = fieldFocus,
                                onTapChip = { beginEdit(it) },
                                onRemoveChip = { remove(it) },
                                onCommitEdit = { commitEdit() },
                                onBeginAdd = { beginAdd() },
                                onCommitAndContinueAdd = { commitAndContinueAdd() },
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                        item { SectionLabel("PRESETS") }
                        item { PresetRail(onInsert = { insertPreset(it) }) }

                        if (runs.isNotEmpty()) {
                            item {
                                ResultsHeader(
                                    hasLiked = runs.any { it.liked },
                                    showLikedOnly = showLikedOnly,
                                    onToggle = { showLikedOnly = !showLikedOnly },
                                )
                            }
                            val filtered = if (showLikedOnly) runs.filter { it.liked } else runs.toList()
                            for (batch in batched(filtered)) {
                                item(key = "batch-${batch.id}") { BatchHeader(batch.createdAt) }
                                items(batch.runs.size, key = { batch.runs[it].id.toString() }) { i ->
                                    val run = batch.runs[i]
                                    // Disk rows arrive from loadRuns() without pixels; read +
                                    // decode this row's file only once it is composed (visible).
                                    // Generation rows never match: their filename is empty until
                                    // saved, and saved ones already carry their image. On decode
                                    // failure drop the row — same as the eager loader's `continue`.
                                    LaunchedEffect(run.id) {
                                        if (run.image == null && run.imageFilename.isNotEmpty()) {
                                            val img = runCatching {
                                                readFileBytes(run.imageFilename).toByteArray()
                                            }.getOrNull()?.let { decodeImageBitmap(it) }
                                            val idx = runs.indexOfFirst { it.id == run.id }
                                            if (idx >= 0) {
                                                if (img != null) runs[idx] = runs[idx].copy(image = img)
                                                else runs.removeAt(idx)
                                            }
                                        }
                                    }
                                    ResultRow(
                                        run = run,
                                        active = isActive(run),
                                        joinedPrompt = joinedPrompt(run),
                                        onRestore = { restore(run) },
                                        onLike = { toggleLike(run) },
                                        onRetry = { retry(run) },
                                        onRemove = { removeRun(run) },
                                    )
                                }
                            }
                        }
                    }

                    if (!editorVisible && chips.isNotEmpty()) {
                        BackToEditorPill(
                            text = chips.joinToString(" · ") { it.text },
                            onTap = { scope.launch { listState.animateScrollToItem(0) } },
                            modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp),
                        )
                    }
                }

                GenerateButton(
                    enabled = chips.isNotEmpty(),
                    cost = costPerGenerate,
                    onClick = { generate() },
                    modifier = Modifier.padding(horizontal = 22.dp).padding(bottom = 14.dp),
                )
            }

            if (pendingUndos.isNotEmpty()) {
                UndoToast(
                    count = pendingUndos.size,
                    onUndo = { undoRemove() },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .widthIn(max = 620.dp)
                        .padding(horizontal = 22.dp)
                        .padding(bottom = 88.dp),
                )
            }
        }
    }
}

// MARK: - Header

@Composable
private fun Header() {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(8.dp)
                .clip(RoundedCornerShape(50))
                .background(Brush.horizontalGradient(listOf(Purple, Pink))),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            "ENGINEER",
            color = Color.White.copy(alpha = 0.85f),
            fontFamily = LocalBrandFont.current,
            fontSize = 12.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 2.8.sp,
        )
    }
}

@Composable
private fun BackToEditorPill(text: String, onTap: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .widthIn(max = 320.dp)
            .clip(RoundedCornerShape(50))
            .background(Brush.horizontalGradient(listOf(Purple.copy(alpha = 0.92f), Pink.copy(alpha = 0.92f))))
            .border(0.7.dp, Color.White.copy(alpha = 0.3f), RoundedCornerShape(50))
            .bounceClick(onTap)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            color = Color.White,
            fontFamily = LocalBrandFont.current,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Spacer(Modifier.width(8.dp))
        Icon(Icons.Default.KeyboardArrowUp, contentDescription = null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun UndoToast(count: Int, onUndo: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.Black.copy(alpha = 0.7f))
            .border(0.5.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Default.Delete, contentDescription = null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(12.dp))
        Text(
            if (count > 1) "$count results removed" else "Result removed",
            color = Color.White,
            fontFamily = LocalBrandFont.current,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        Text(
            "Undo",
            modifier = Modifier.clickable { onUndo() }.padding(horizontal = 10.dp, vertical = 6.dp),
            color = Pink,
            fontFamily = LocalBrandFont.current,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

// MARK: - Prompt header + section label

@Composable
private fun PromptHeader(hasChips: Boolean, onClear: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        SectionLabel("PROMPT")
        Spacer(Modifier.weight(1f))
        if (hasChips) {
            Text(
                "CLEAR",
                modifier = Modifier
                    .padding(end = 22.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.05f))
                    .border(0.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
                    .clickable { onClear() }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                color = Color.White.copy(alpha = 0.5f),
                fontFamily = LocalBrandFont.current,
                fontSize = 10.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.5.sp,
            )
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        modifier = Modifier.padding(horizontal = 22.dp),
        color = Color.White.copy(alpha = 0.45f),
        fontFamily = LocalBrandFont.current,
        fontSize = 10.sp,
        fontWeight = FontWeight.Black,
        letterSpacing = 2.sp,
    )
}

// MARK: - Chip flow

@Composable
private fun ChipFlow(
    chips: List<Chip>,
    editingId: Uuid?,
    editingText: String,
    onEditingTextChange: (String) -> Unit,
    addingNew: Boolean,
    newChipText: String,
    onNewChipTextChange: (String) -> Unit,
    atCap: Boolean,
    fieldFocus: FocusRequester,
    onTapChip: (Chip) -> Unit,
    onRemoveChip: (Chip) -> Unit,
    onCommitEdit: () -> Unit,
    onBeginAdd: () -> Unit,
    onCommitAndContinueAdd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            chips.forEach { chip ->
                if (editingId == chip.id) {
                    Box(
                        Modifier
                            .clip(RoundedCornerShape(50))
                            .background(Color.White.copy(alpha = 0.14f))
                            .border(0.7.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(50))
                            .padding(horizontal = 14.dp, vertical = 7.dp),
                    ) {
                        AutoChipField(
                            text = editingText,
                            onValueChange = onEditingTextChange,
                            placeholder = "",
                            imeAction = ImeAction.Done,
                            onSubmit = onCommitEdit,
                            focusRequester = fieldFocus,
                        )
                    }
                } else {
                    Row(
                        Modifier
                            .clip(RoundedCornerShape(50))
                            .background(Color.White.copy(alpha = 0.08f))
                            .border(0.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
                            .padding(start = 14.dp, end = 5.dp, top = 7.dp, bottom = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            chip.text,
                            modifier = Modifier.widthIn(max = 300.dp).clickable { onTapChip(chip) },
                            color = Color.White.copy(alpha = 0.92f),
                            fontFamily = LocalBrandFont.current,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.width(6.dp))
                        Box(
                            Modifier
                                .size(22.dp)
                                .clip(RoundedCornerShape(50))
                                .background(Color.White.copy(alpha = 0.10f))
                                .clickable { onRemoveChip(chip) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Default.Close, contentDescription = "Remove", tint = Color.White.copy(alpha = 0.6f), modifier = Modifier.size(12.dp))
                        }
                    }
                }
            }

            // Add-chip affordance.
            if (!(atCap && !addingNew)) {
                if (addingNew) {
                    Row(
                        Modifier
                            .clip(RoundedCornerShape(50))
                            .background(Color.White.copy(alpha = 0.14f))
                            .border(0.7.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(50))
                            .padding(horizontal = 14.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null, tint = Color.White.copy(alpha = 0.6f), modifier = Modifier.size(12.dp))
                        Spacer(Modifier.width(4.dp))
                        AutoChipField(
                            text = newChipText,
                            onValueChange = onNewChipTextChange,
                            placeholder = "phrase",
                            imeAction = ImeAction.Next,
                            onSubmit = onCommitAndContinueAdd,
                            focusRequester = fieldFocus,
                        )
                    }
                } else {
                    Row(
                        Modifier
                            .clip(RoundedCornerShape(50))
                            .background(Color.White.copy(alpha = 0.04f))
                            .border(0.7.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(50))
                            .clickable { onBeginAdd() }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null, tint = Color.White.copy(alpha = 0.55f), modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(
                            "add",
                            color = Color.White.copy(alpha = 0.55f),
                            fontFamily = LocalBrandFont.current,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
        if (chips.isEmpty() && !addingNew) {
            Text(
                "tap + to begin engineering your prompt",
                modifier = Modifier.padding(top = 10.dp),
                color = Color.White.copy(alpha = 0.35f),
                fontFamily = LocalBrandFont.current,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

/// Auto-sizing single-line field: an invisible mirror Text establishes the width
/// (clamped 60…240), the BasicTextField fills it — mirrors Swift's measuringMirror.
@Composable
private fun AutoChipField(
    text: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    imeAction: ImeAction,
    onSubmit: () -> Unit,
    focusRequester: FocusRequester,
) {
    val style = TextStyle(
        color = Color.White,
        fontFamily = LocalBrandFont.current,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
    )
    LaunchedEffect(Unit) { runCatching { focusRequester.requestFocus() } }
    Box(contentAlignment = Alignment.CenterStart) {
        // Mirror sizes the box; clamp width.
        Text(
            text.ifEmpty { placeholder.ifEmpty { " " } },
            style = style,
            maxLines = 1,
            modifier = Modifier.widthIn(min = 60.dp, max = 240.dp).alpha(0f),
        )
        BasicTextField(
            value = text,
            onValueChange = onValueChange,
            modifier = Modifier.matchParentSize().focusRequester(focusRequester),
            singleLine = true,
            textStyle = style,
            cursorBrush = SolidColor(Pink),
            keyboardOptions = KeyboardOptions(imeAction = imeAction),
            keyboardActions = KeyboardActions(onDone = { onSubmit() }, onNext = { onSubmit() }),
            decorationBox = { inner ->
                if (text.isEmpty() && placeholder.isNotEmpty()) {
                    Text(placeholder, style = style.copy(color = Color.White.copy(alpha = 0.35f)), maxLines = 1)
                }
                inner()
            },
        )
    }
}

// MARK: - Preset rail

@Composable
private fun PresetRail(onInsert: (String) -> Unit) {
    val presets = listOf("Cinematic", "Neon", "Moody", "Pastel", "Film", "Surreal", "Vintage", "Dreamy")
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 22.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        presets.forEach { p ->
            Text(
                p,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.06f))
                    .border(0.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
                    .clickable { onInsert(p) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                color = Color.White.copy(alpha = 0.85f),
                fontFamily = LocalBrandFont.current,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

// MARK: - Results

@Composable
private fun ResultsHeader(hasLiked: Boolean, showLikedOnly: Boolean, onToggle: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        SectionLabel("RESULTS")
        Spacer(Modifier.weight(1f))
        if (hasLiked) {
            Row(
                modifier = Modifier
                    .padding(end = 22.dp)
                    .clip(RoundedCornerShape(50))
                    .background(if (showLikedOnly) Pink.copy(alpha = 0.15f) else Color.White.copy(alpha = 0.05f))
                    .border(
                        0.5.dp,
                        if (showLikedOnly) Pink.copy(alpha = 0.5f) else Color.White.copy(alpha = 0.12f),
                        RoundedCornerShape(50),
                    )
                    .clickable { onToggle() }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (showLikedOnly) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                    contentDescription = null,
                    tint = if (showLikedOnly) Pink else Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.size(11.dp),
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    "LIKED",
                    color = if (showLikedOnly) Pink else Color.White.copy(alpha = 0.5f),
                    fontFamily = LocalBrandFont.current,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 1.5.sp,
                )
            }
        }
    }
}

@Composable
private fun BatchHeader(createdAt: Double) {
    Row(
        modifier = Modifier.padding(horizontal = 22.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("GENERATED", color = Color.White.copy(alpha = 0.4f), fontFamily = LocalBrandFont.current, fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp)
        Text("·", color = Color.White.copy(alpha = 0.4f), fontSize = 9.sp, fontWeight = FontWeight.Black)
        Text(relativeString(createdAt), color = Color.White.copy(alpha = 0.4f), fontFamily = LocalBrandFont.current, fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 0.8.sp)
    }
}

@Composable
private fun ResultRow(
    run: Run,
    active: Boolean,
    joinedPrompt: String,
    onRestore: () -> Unit,
    onLike: () -> Unit,
    onRetry: () -> Unit,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier
            .padding(horizontal = 22.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White.copy(alpha = if (active) 0.08f else 0.04f))
            .then(
                if (active) {
                    Modifier.border(1.2.dp, Brush.horizontalGradient(listOf(Purple, Pink)), RoundedCornerShape(16.dp))
                } else {
                    Modifier.border(0.5.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
                },
            )
            .bounceClick(onRestore)
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Thumbnail(run)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                joinedPrompt,
                color = Color.White.copy(alpha = 0.82f),
                fontFamily = LocalBrandFont.current,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "${run.chips.size} ${if (run.chips.size == 1) "phrase" else "phrases"}",
                color = Color.White.copy(alpha = 0.4f),
                fontFamily = LocalBrandFont.current,
                fontSize = 9.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.2.sp,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (run.state == RunState.Failed) {
                CircleIconButton(Icons.Default.Refresh, Color.White.copy(alpha = 0.8f), Color.White.copy(alpha = 0.10f), onRetry)
            } else {
                CircleIconButton(
                    if (run.liked) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                    if (run.liked) Pink else Color.White.copy(alpha = 0.55f),
                    Color.White.copy(alpha = 0.06f),
                    onLike,
                )
            }
            CircleIconButton(Icons.Default.Close, Color.White.copy(alpha = 0.5f), Color.White.copy(alpha = 0.06f), onRemove)
        }
    }
}

@Composable
private fun CircleIconButton(icon: ImageVector, tint: Color, bg: Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier.size(28.dp).clip(RoundedCornerShape(50)).background(bg).clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(15.dp))
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
            RunState.Loading -> Shimmer(Modifier.matchParentSize())
            RunState.Loaded -> run.image?.let {
                Image(bitmap = it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
            }
            RunState.Failed -> Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.45f)), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Warning, contentDescription = null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(26.dp))
            }
        }
    }
}

// MARK: - Generate button

@Composable
private fun GenerateButton(enabled: Boolean, cost: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(58.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.horizontalGradient(listOf(Purple, Pink)))
            .border(0.7.dp, Color.White.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
            .alpha(if (enabled) 1f else 0.5f)
            .clickable(enabled = enabled) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Generate", color = Color.White, fontFamily = LocalBrandFont.current, fontSize = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.5.sp)
                Text("$cost credits", color = Color.White.copy(alpha = 0.7f), fontFamily = LocalBrandFont.current, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp)
            }
        }
    }
}

// MARK: - Shimmer + palettes + relative time

@Composable
private fun Shimmer(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val phase by transition.animateFloat(
        initialValue = -1f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing)),
        label = "phase",
    )
    Box(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(
                Brush.horizontalGradient(
                    0f to Color.White.copy(alpha = 0f),
                    (0.5f + phase * 0.4f).coerceIn(0.001f, 0.999f) to Color.White.copy(alpha = 0.35f),
                    1f to Color.White.copy(alpha = 0f),
                ),
            ),
    )
}

private val gradientPalettes: List<List<Color>> = listOf(
    listOf(Color(1.00f, 0.50f, 0.30f), Color(0.80f, 0.20f, 0.50f)),
    listOf(Color(0.30f, 0.50f, 1.00f), Color(0.60f, 0.20f, 0.90f)),
    listOf(Color(0.95f, 0.60f, 0.20f), Color(0.70f, 0.30f, 0.70f)),
    listOf(Color(0.20f, 0.60f, 0.70f), Color(0.50f, 0.80f, 0.50f)),
    listOf(Color(0.60f, 0.20f, 0.40f), Color(0.90f, 0.40f, 0.60f)),
    listOf(Color(0.15f, 0.25f, 0.45f), Color(0.70f, 0.45f, 0.65f)),
)

/// Groups consecutive runs into 2-second createdAt buckets — runs from one
/// Generate tap share a bucket (stamped within ms of each other).
private fun batched(runs: List<Run>): List<RunBatch> {
    val result = mutableListOf<RunBatch>()
    var current = mutableListOf<Run>()
    var currentKey = -1.0
    val bucketMs = 2000.0
    for (run in runs) {
        val key = floor(run.createdAt / bucketMs)
        if (current.isNotEmpty() && key == currentKey) {
            current.add(run)
        } else {
            current.firstOrNull()?.let { result.add(RunBatch(it.id, it.createdAt, current.toList())) }
            current = mutableListOf(run)
            currentKey = key
        }
    }
    current.firstOrNull()?.let { result.add(RunBatch(it.id, it.createdAt, current.toList())) }
    return result
}

private fun relativeString(createdAt: Double): String {
    val diff = (jsDateNow() - createdAt).coerceAtLeast(0.0)
    val s = (diff / 1000.0).toInt()
    return when {
        s < 5 -> "now"
        s < 60 -> "${s}s ago"
        s < 3600 -> "${s / 60}m ago"
        s < 86400 -> "${s / 3600}h ago"
        else -> "${s / 86400}d ago"
    }
}

// MARK: - Press style

@Composable
private fun Modifier.bounceClick(onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.985f else 1f, label = "press")
    return this.scale(scale).clickable(interactionSource = interaction, indication = null, onClick = onClick)
}
