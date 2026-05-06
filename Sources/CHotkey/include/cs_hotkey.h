#ifndef CS_HOTKEY_H
#define CS_HOTKEY_H

#include <stdint.h>

typedef void (*CSHotkeyHandler)(void);

void cs_hotkey_unregister(void);

/// 注册 ⌥␣（或传入 `modifiers` 为 Carbon 的 optionKey、controlKey|optionKey 等）。
/// 成功返回 1，失败返回 0。
int cs_hotkey_register(uint32_t modifiers, CSHotkeyHandler handler);

#endif
