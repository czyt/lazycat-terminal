# LazyCat Terminal

一个使用 Vala 和 VTE 编写的现代化终端模拟器，具有类似 Chrome 的标签页界面和透明背景支持。

## 功能特性

- **Chrome 风格标签页** - 自定义绘制的标签栏，支持多标签页管理
- **透明背景** - 支持窗口和终端透明效果
- **无边框设计** - 使用 CSD (Client-Side Decorations) 实现现代化外观
- **macOS 风格窗口控制** - 红黄绿三色窗口控制按钮
- **终端功能完整** - 基于 VTE，支持 10000 行滚动缓冲区
- **键盘快捷键** - 支持常用的标签页操作快捷键
- **窗口拖拽** - 从标签栏空白区域拖拽移动窗口
- **双击最大化** - 双击标签栏空白区域最大化/还原窗口

## 依赖

构建此项目需要以下依赖：

- **Vala** - Vala 编译器
- **Meson** (>= 0.50.0) - 构建系统
- **GTK4** - GUI 工具包
- **VTE** (vte-2.91-gtk4) - 终端模拟器库

### 各发行版安装依赖

**Arch Linux:**

```bash
sudo pacman -S vala meson gtk4 vte4
```

**Debian/Ubuntu:**

```bash
sudo apt install valac meson libgtk-4-dev libvte-2.91-gtk4-dev
```

**Fedora:**

```bash
sudo dnf install vala meson gtk4-devel vte291-gtk4-devel
```

## 构建

### 编译

```bash
# 配置构建目录
meson setup build

# 编译
meson compile -C build
```

### 安装

```bash
# 安装到系统 (需要 root 权限)
sudo meson install -C build
```

### 运行

```bash
# 直接运行编译后的可执行文件
./build/lazycat-terminal

# 或者安装后运行
lazycat-terminal
```

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+Shift+T` | 新建标签页 |
| `Ctrl+Shift+W` | 关闭当前标签页 |
| `Ctrl+Shift+Tab` | 切换到上一个标签页 |
| `Ctrl+Shift+Tab` (反向) | 切换到下一个标签页 |
| `Ctrl+PageUp` | 切换到上一个标签页 |
| `Ctrl+PageDown` | 切换到下一个标签页 |

## 项目结构

```
lazycat-terminal/
├── meson.build          # Meson 构建配置文件
├── src/
│   ├── main.vala        # 程序入口，GtkApplication 定义
│   ├── window.vala      # 主窗口，包含标签页管理和快捷键
│   ├── tab_bar.vala     # Chrome 风格标签栏的自定义绘制
│   └── terminal_tab.vala # VTE 终端封装
├── LICENSE              # GPL-3.0 许可证
└── README.md            # 本文件
```

## 许可证

本项目采用 [GNU General Public License v3.0](LICENSE) 许可证。
