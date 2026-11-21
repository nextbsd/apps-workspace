ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make
APP_NAME = Workspace
Workspace_OBJC_FILES = main.m FVApplication.m FVWindow.m FVModel.m FVOperations.m FVIconView.m FVLauncher.m FVThumbnails.m FVPanels.m FVInspector.m FVDesktopSettings.m FVBackground.m FVBackgroundSettings.m FVDesktop.m FVDockSettings.m
Workspace_HEADER_FILES = FVApplication.h FVWindow.h FVModel.h FVOperations.h FVIconView.h FVLauncher.h FVThumbnails.h FVPanels.h FVInspector.h FVDesktopSettings.h FVBackground.h FVBackgroundSettings.h FVDesktop.h FVDockSettings.h
Workspace_RESOURCE_FILES = Resources/Workspace.png Resources/HardDisk.tiff Resources/WorkspaceHelp.rtf \
  Background/obj/WorkspaceBackground
Workspace_APPLICATION_ICON = Workspace.png
Workspace_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
ADDITIONAL_GUI_LIBS += -lX11 -lXext
ifneq (,$(findstring linux,$(GNUSTEP_TARGET_OS)))
ADDITIONAL_GUI_LIBS += -lmount
endif
# The desktop background, built first and kept in Workspace.app's Resources.
SUBPROJECTS = Background
include $(GNUSTEP_MAKEFILES)/aggregate.make
include $(GNUSTEP_MAKEFILES)/application.make
