package com.meta.wearable.dat.externalsampleapps.cameraaccess.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DismissDirection
import androidx.compose.material3.DismissValue
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SwipeToDismiss
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDismissState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.JarvisChat
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.JarvisVoiceSession
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.launch

private val Black = Color.Black
private val White = Color.White
private val ActiveBlue = Color(0xFF007AFF)
private val SubtleWhite = Color(0x1AFFFFFF)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatListScreen(
    session: JarvisVoiceSession,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val chatList by session.chatList.collectAsState()
    val activeChatId by session.activeChatId.collectAsState()
    val scope = rememberCoroutineScope()

    var searchText by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var renameTarget by remember { mutableStateOf<JarvisChat?>(null) }
    var renameText by remember { mutableStateOf("") }
    var selectedChat by remember { mutableStateOf<JarvisChat?>(null) }

    LaunchedEffect(Unit) {
        isLoading = true
        session.loadChatList()
        isLoading = false
    }

    val filtered = if (searchText.isEmpty()) chatList
    else chatList.filter {
        it.title.contains(searchText, ignoreCase = true) ||
        it.previewText.contains(searchText, ignoreCase = true)
    }

    if (selectedChat != null) {
        ChatDetailScreen(
            chat = selectedChat!!,
            session = session,
            onDone = onDismiss,
            onBack = { selectedChat = null },
        )
        return
    }

    Column(
        modifier = modifier.fillMaxSize().background(Black),
    ) {
        TopAppBar(
            title = { Text("Chats", color = White) },
            navigationIcon = {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close", tint = White)
                }
            },
            actions = {
                IconButton(onClick = {
                    scope.launch {
                        session.newChat()
                        onDismiss()
                    }
                }) {
                    Icon(Icons.Default.Add, contentDescription = "New Chat", tint = White)
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Black),
        )

        OutlinedTextField(
            value = searchText,
            onValueChange = { searchText = it },
            placeholder = { Text("Search conversations", color = White.copy(alpha = 0.4f)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = White,
                unfocusedTextColor = White,
                focusedBorderColor = White.copy(alpha = 0.3f),
                unfocusedBorderColor = White.copy(alpha = 0.15f),
            ),
        )

        when {
            isLoading && chatList.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = White)
                }
            }
            filtered.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        if (searchText.isEmpty()) "No conversations yet" else "No results",
                        color = White.copy(alpha = 0.4f),
                        fontSize = 15.sp,
                    )
                }
            }
            else -> {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    items(filtered, key = { it.id }) { chat ->
                        val dismissState = rememberDismissState(
                            confirmValueChange = { dismissValue ->
                                if (dismissValue == DismissValue.DismissedToStart && chat.id != "main") {
                                    session.deleteChat(chat)
                                    true
                                } else false
                            }
                        )
                        SwipeToDismiss(
                            state = dismissState,
                            directions = if (chat.id == "main") emptySet()
                            else setOf(DismissDirection.EndToStart),
                            background = {
                                Box(
                                    modifier = Modifier.fillMaxSize().background(Color(0xFFFF3B30)),
                                    contentAlignment = Alignment.CenterEnd,
                                ) {
                                    Text(
                                        "Delete",
                                        color = White,
                                        modifier = Modifier.padding(end = 20.dp),
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            },
                            dismissContent = {
                                ChatRow(
                                    chat = chat,
                                    isActive = chat.id == activeChatId,
                                    onClick = { selectedChat = chat },
                                    onRename = {
                                        renameTarget = chat
                                        renameText = chat.title
                                    },
                                )
                            },
                        )
                        HorizontalDivider(color = White.copy(alpha = 0.08f))
                    }
                }
            }
        }
    }

    if (renameTarget != null) {
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("Rename", color = White) },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    label = { Text("Chat name", color = White.copy(alpha = 0.6f)) },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = White,
                        unfocusedTextColor = White,
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val trimmed = renameText.trim()
                    if (trimmed.isNotEmpty()) {
                        renameTarget?.let { session.renameChat(it.id, trimmed) }
                    }
                    renameTarget = null
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) { Text("Cancel") }
            },
            containerColor = Color(0xFF1C1C1E),
        )
    }
}

@Composable
private fun ChatRow(
    chat: JarvisChat,
    isActive: Boolean,
    onClick: () -> Unit,
    onRename: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(if (isActive) ActiveBlue else White.copy(alpha = 0.2f)),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                chat.title,
                color = White,
                fontSize = 16.sp,
                fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
            )
            if (chat.previewText.isNotEmpty()) {
                Text(
                    chat.previewText,
                    color = White.copy(alpha = 0.45f),
                    fontSize = 13.sp,
                    maxLines = 1,
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        Text(
            chatTimestamp(chat.updatedAt),
            color = White.copy(alpha = 0.35f),
            fontSize = 12.sp,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChatDetailScreen(
    chat: JarvisChat,
    session: JarvisVoiceSession,
    onDone: () -> Unit,
    onBack: () -> Unit,
) {
    val messages by session.messages.collectAsState()
    var isLoading by remember { mutableStateOf(true) }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    val scope = rememberCoroutineScope()

    LaunchedEffect(chat.id) {
        isLoading = true
        session.switchChat(chat)
        isLoading = false
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Black)) {
        TopAppBar(
            title = {
                Text(chat.title, color = White, maxLines = 1)
            },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = White)
                }
            },
            actions = {
                TextButton(onClick = onDone) {
                    Text("Done", color = White)
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = Black),
        )

        when {
            isLoading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = White)
                }
            }
            messages.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("No messages yet", color = White.copy(alpha = 0.4f), fontSize = 15.sp)
                }
            }
            else -> {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 12.dp),
                ) {
                    items(messages, key = { it.id }) { message ->
                        ChatBubbleItem(message = message)
                        Spacer(Modifier.height(10.dp))
                    }
                }
            }
        }
    }
}

private fun chatTimestamp(millis: Long): String {
    val cal = Calendar.getInstance()
    val today = cal.clone() as Calendar
    cal.timeInMillis = millis
    return when {
        isSameDay(cal, today) -> SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(millis))
        isYesterday(cal, today) -> "Yesterday"
        else -> SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(millis))
    }
}

private fun isSameDay(a: Calendar, b: Calendar): Boolean =
    a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
    a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

private fun isYesterday(day: Calendar, today: Calendar): Boolean {
    val yesterday = today.clone() as Calendar
    yesterday.add(Calendar.DAY_OF_YEAR, -1)
    return isSameDay(day, yesterday)
}
