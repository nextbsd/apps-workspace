ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make

# The desktop background: InnerSpace's host, which Workspace starts from
# its Resources. A tool, not an application: no bundle, no icon, nothing
# for the Dock or the Applications folder. It links AppKit, since the
# modules are views. The modules come from apps-innerspace, installed in
# a Library's InnerSpace folder.
TOOL_NAME = WorkspaceBackground
WorkspaceBackground_OBJC_FILES = main.m SaverWindow.m InnerSpaceController.m
WorkspaceBackground_C_FILES = UtilFunctions.c
WorkspaceBackground_HEADER_FILES = InnerSpaceController.h SaverWindow.h ModuleView.h WorkspaceBackground.h
WorkspaceBackground_NEEDS_GUI = yes
WorkspaceBackground_STANDARD_INSTALL = no
# SaverWindow lowers itself under X (XLowerWindow).
ADDITIONAL_CPPFLAGS += $(shell pkg-config --cflags x11 2>/dev/null)
ADDITIONAL_TOOL_LIBS += $(shell pkg-config --libs x11 2>/dev/null || echo -lX11)
include $(GNUSTEP_MAKEFILES)/tool.make
