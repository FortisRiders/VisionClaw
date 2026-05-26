package com.meta.wearable.dat.externalsampleapps.cameraaccess.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.ChatMessage
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.JarvisVoiceSession
import kotlinx.coroutines.delay

private val Black = Color.Black
private val White = Color.White
private val ChatActiveBlue = Color(0xFF007AFF)
private val ChatRed = Color(0xFFFF3B30)
private val ChatSpeakingBlue = Color(0xFF3373F2)
private val ChatIdleGray = Color(0x2EFFFFFF)

@Composable
fun JarvisPTTScreen(
    session: JarvisVoiceSession,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by session.state.collectAsState()
    val messages by session.messages.collectAsState()
    val liveTranscript by session.liveTranscript.collectAsState()
    val activeChatTitle = session.activeChatTitle
    val errorMessage by session.errorMessage.collectAsState()

    var showChatList by remember { mutableStateOf(false) }
    var isTextMode by remember { mutableStateOf(false) }
    var textInput by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    LaunchedEffect(errorMessage) {
        if (errorMessage != null) {
            delay(3000)
            session.clearError()
        }
    }

    if (showChatList) {
        ChatListScreen(
            session = session,
            onDismiss = { showChatList = false },
        )
        return
    }

    Column(
        modifier = modifier.fillMaxSize().background(Black),
    ) {
        PTTHeader(
            title = activeChatTitle,
            onClose = {
                session.cancel()
                onDismiss()
            },
            onOpenChats = { showChatList = true },
        )

        Box(modifier = Modifier.weight(1f)) {
            if (messages.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        "Press and hold to talk to Jarvis",
                        color = White.copy(alpha = 0.35f),
                        fontSize = 15.sp,
                    )
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 12.dp),
                    contentPadding = PaddingValues(bottom = 8.dp),
                ) {
                    items(messages, key = { it.id }) { message ->
                        ChatBubbleItem(message = message)
                        Spacer(Modifier.height(10.dp))
                    }
                }
            }
        }

        TranscriptArea(state = state, transcript = liveTranscript)

        Spacer(Modifier.height(16.dp))

        if (isTextMode) {
            TextInputBar(
                text = textInput,
                onTextChange = { textInput = it },
                onSend = {
                    val trimmed = textInput.trim()
                    if (trimmed.isNotEmpty() && state == JarvisVoiceSession.State.IDLE) {
                        session.sendText(trimmed)
                        textInput = ""
                        keyboardController?.hide()
                    }
                },
                onMicClick = {
                    isTextMode = false
                    keyboardController?.hide()
                },
                isDisabled = state != JarvisVoiceSession.State.IDLE,
                focusRequester = focusRequester,
            )
            LaunchedEffect(isTextMode) {
                if (isTextMode) {
                    delay(150)
                    focusRequester.requestFocus()
                }
            }
        } else {
            VoiceBar(
                state = state,
                onPressStart = {
                    if (state == JarvisVoiceSession.State.IDLE) session.startListening()
                },
                onPressEnd = {
                    if (state == JarvisVoiceSession.State.LISTENING) session.stopListeningAndSend()
                },
                onKeyboardClick = { isTextMode = true },
            )
        }

        Spacer(Modifier.height(32.dp))
    }
}

@Composable
private fun PTTHeader(
    title: String,
    onClose: () -> Unit,
    onOpenChats: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onClose) {
            Icon(Icons.Default.Close, contentDescription = "Close", tint = White)
        }
        Spacer(Modifier.weight(1f))
        Text(
            title,
            color = White,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
        Spacer(Modifier.weight(1f))
        IconButton(onClick = onOpenChats) {
            Icon(Icons.Default.Menu, contentDescription = "Chats", tint = White.copy(alpha = 0.7f))
        }
    }
}

@Composable
private fun TranscriptArea(
    state: JarvisVoiceSession.State,
    transcript: String,
) {
    Box(
        modifier = Modifier.fillMaxWidth().height(44.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            state == JarvisVoiceSession.State.SENDING -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = White.copy(alpha = 0.6f),
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text("Thinking…", color = White.copy(alpha = 0.6f), fontSize = 14.sp)
                }
            }
            transcript.isNotEmpty() -> {
                Text(
                    transcript,
                    color = White.copy(alpha = 0.6f),
                    fontSize = 14.sp,
                    maxLines = 1,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }
        }
    }
}

@Composable
private fun VoiceBar(
    state: JarvisVoiceSession.State,
    onPressStart: () -> Unit,
    onPressEnd: () -> Unit,
    onKeyboardClick: () -> Unit,
) {
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center,
    ) {
        PTTButton(state = state, onPressStart = onPressStart, onPressEnd = onPressEnd)
        Box(modifier = Modifier.align(Alignment.CenterEnd).padding(end = 24.dp)) {
            IconButton(onClick = onKeyboardClick) {
                Icon(
                    imageVector = Icons.Default.Mic,
                    contentDescription = "Text mode",
                    tint = White.copy(alpha = 0.6f),
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@Composable
private fun PTTButton(
    state: JarvisVoiceSession.State,
    onPressStart: () -> Unit,
    onPressEnd: () -> Unit,
) {
    val isDisabled = state == JarvisVoiceSession.State.SENDING || state == JarvisVoiceSession.State.SPEAKING
    val isPulsing = state == JarvisVoiceSession.State.LISTENING

    val infiniteTransition = rememberInfiniteTransition(label = "ptt-pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 0.85f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(900),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse",
    )

    val buttonColor = when (state) {
        JarvisVoiceSession.State.IDLE -> ChatIdleGray
        JarvisVoiceSession.State.LISTENING -> ChatRed
        JarvisVoiceSession.State.SENDING -> Color.Gray.copy(alpha = 0.45f)
        JarvisVoiceSession.State.SPEAKING -> ChatSpeakingBlue
    }

    val buttonIcon: ImageVector = when (state) {
        JarvisVoiceSession.State.IDLE, JarvisVoiceSession.State.LISTENING -> Icons.Default.Mic
        JarvisVoiceSession.State.SENDING, JarvisVoiceSession.State.SPEAKING -> Icons.Default.Mic
    }

    val buttonLabel: String? = when (state) {
        JarvisVoiceSession.State.IDLE -> "Hold to Talk"
        JarvisVoiceSession.State.LISTENING -> "Listening..."
        JarvisVoiceSession.State.SENDING -> null
        JarvisVoiceSession.State.SPEAKING -> "Speaking"
    }

    Box(
        modifier = Modifier.size(152.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (isPulsing) {
            Box(
                modifier = Modifier
                    .size(152.dp)
                    .scale(pulseScale)
                    .clip(CircleShape)
                    .background(buttonColor.copy(alpha = 0.25f)),
            )
        }

        Box(
            modifier = Modifier
                .size(120.dp)
                .clip(CircleShape)
                .background(buttonColor)
                .pointerInput(isDisabled) {
                    if (!isDisabled) {
                        detectTapGestures(
                            onPress = {
                                onPressStart()
                                tryAwaitRelease()
                                onPressEnd()
                            }
                        )
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            if (state == JarvisVoiceSession.State.SENDING) {
                CircularProgressIndicator(color = White, modifier = Modifier.size(36.dp))
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        imageVector = buttonIcon,
                        contentDescription = "PTT",
                        tint = White,
                        modifier = Modifier.size(30.dp),
                    )
                    if (buttonLabel != null) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            buttonLabel,
                            color = White.copy(alpha = 0.85f),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TextInputBar(
    text: String,
    onTextChange: (String) -> Unit,
    onSend: () -> Unit,
    onMicClick: () -> Unit,
    isDisabled: Boolean,
    focusRequester: FocusRequester,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onMicClick) {
            Icon(Icons.Default.Mic, contentDescription = "Voice mode", tint = White.copy(alpha = 0.7f))
        }

        OutlinedTextField(
            value = text,
            onValueChange = onTextChange,
            placeholder = { Text("Message Jarvis…", color = White.copy(alpha = 0.4f)) },
            singleLine = true,
            modifier = Modifier.weight(1f).focusRequester(focusRequester),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = White,
                unfocusedTextColor = White,
                focusedBorderColor = White.copy(alpha = 0.3f),
                unfocusedBorderColor = White.copy(alpha = 0.15f),
            ),
            shape = RoundedCornerShape(24.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSend() }),
        )

        Spacer(Modifier.width(8.dp))

        Button(
            onClick = onSend,
            enabled = text.trim().isNotEmpty() && !isDisabled,
            colors = ButtonDefaults.buttonColors(
                containerColor = ChatActiveBlue,
                disabledContainerColor = White.copy(alpha = 0.2f),
            ),
            shape = CircleShape,
            contentPadding = PaddingValues(0.dp),
            modifier = Modifier.size(44.dp),
        ) {
            Icon(Icons.Default.KeyboardArrowUp, contentDescription = "Send", tint = White)
        }
    }
}

@Composable
fun ChatBubbleItem(message: ChatMessage) {
    val isUser = message.role == ChatMessage.Role.USER
    val bubbleColor = if (isUser) ChatActiveBlue else Color(0xFF333333)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom,
    ) {
        if (isUser) Spacer(Modifier.width(60.dp))

        if (!isUser) {
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(Color(0xFF404040)),
                contentAlignment = Alignment.Center,
            ) {
                Text("J", color = White.copy(alpha = 0.8f), fontSize = 13.sp, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.width(6.dp))
        }

        Text(
            message.text,
            color = White,
            fontSize = 16.sp,
            modifier = Modifier
                .clip(RoundedCornerShape(18.dp))
                .background(bubbleColor)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        )

        if (!isUser) Spacer(Modifier.width(60.dp))
    }
}
