ifneq ($(V),1)
.SILENT:
endif

.PHONY: all objdir cleantarget clean realclean distclean

# CORE VARIABLES

MODULE := eCSockets
VERSION := 0.0.1
CONFIG := release
ifndef COMPILER
COMPILER := default
endif

TARGET_TYPE = sharedlib

# FLAGS

ECFLAGS =
ifndef DEBIAN_PACKAGE
CFLAGS =
LDFLAGS =
endif
PRJ_CFLAGS =
CECFLAGS =
OFLAGS =
LIBS =

ifdef DEBUG
NOSTRIP := y
endif

CONSOLE = -mwindows

# INCLUDES

SOCKETS_ABSPATH := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

ifndef EC_SDK_SRC
EC_SDK_SRC := $(SOCKETS)../eC
endif

_CF_DIR = $(EC_SDK_SRC)/

include $(_CF_DIR)crossplatform.mk
include $(_CF_DIR)default.cf

# POST-INCLUDES VARIABLES

OBJ = obj/$(CONFIG).$(PLATFORM)$(COMPILER_SUFFIX)$(DEBUG_SUFFIX)/

RES =

TARGET_NAME := eCSockets

TARGET = obj/$(CONFIG).$(PLATFORM)$(COMPILER_SUFFIX)$(DEBUG_SUFFIX)/$(LP)$(TARGET_NAME)$(OUT)

_ECSOURCES = \
	network.ec \
	Service.ec \
	Socket.ec

ECSOURCES = $(call shwspace,$(_ECSOURCES))

_COBJECTS = $(addprefix $(OBJ),$(patsubst %.ec,%$(C),$(notdir $(_ECSOURCES))))

_SYMBOLS = $(addprefix $(OBJ),$(patsubst %.ec,%$(S),$(notdir $(_ECSOURCES))))

_IMPORTS = $(addprefix $(OBJ),$(patsubst %.ec,%$(I),$(notdir $(_ECSOURCES))))

_ECOBJECTS = $(addprefix $(OBJ),$(patsubst %.ec,%$(O),$(notdir $(_ECSOURCES))))

_BOWLS = $(addprefix $(OBJ),$(patsubst %.ec,%$(B),$(notdir $(_ECSOURCES))))

COBJECTS = $(call shwspace,$(_COBJECTS))

SYMBOLS = $(call shwspace,$(_SYMBOLS))

IMPORTS = $(call shwspace,$(_IMPORTS))

ECOBJECTS = $(call shwspace,$(_ECOBJECTS))

BOWLS = $(call shwspace,$(_BOWLS))

OBJECTS = $(ECOBJECTS) $(OBJ)$(MODULE).main$(O)

SOURCES = $(ECSOURCES)

RESOURCES =

ifdef USE_RESOURCES_EAR
RESOURCES_EAR =
else
RESOURCES_EAR = $(RESOURCES)
endif

LIBS += $(SHAREDLIB) $(EXECUTABLE) $(LINKOPT)

ifndef STATIC_LIBRARY_TARGET
OFLAGS += -L$(EC_SDK_SRC)/$(SODESTDIR)
LIBS += \
	$(call _L,ecrt)
endif

PRJ_CFLAGS += \
	 $(if $(DEBUG), -g, -O2 -ffast-math) $(FPIC) -Wall -DREPOSITORY_VERSION="\"$(REPOSITORY_VER)\"" \
			 -DIMPORT_STATIC=\"\"

ECFLAGS += -module $(MODULE)
CECFLAGS += -cpp $(_CPP)

# PLATFORM-SPECIFIC OPTIONS

ifdef WINDOWS_TARGET

ifndef STATIC_LIBRARY_TARGET
OFLAGS +=  -static-libgcc -static-libstdc++

LIBS += \
	-Wl,-Bdynamic \
	$(call _L,ws2_32) \
	-Wl,-Bstatic
endif

else
ifdef LINUX_TARGET

ifndef STATIC_LIBRARY_TARGET

LIBS +=

endif

else
ifdef OSX_TARGET

ifndef STATIC_LIBRARY_TARGET
LIBS +=

endif

endif
endif
endif

# TARGETS

all: objdir $(TARGET)

objdir:
	$(if $(wildcard $(OBJ)),,$(call mkdir,$(OBJ)))
	$(if $(ECERE_SDK_SRC),$(if $(wildcard $(call escspace,$(ECERE_SDK_SRC)/crossplatform.mk)),,@$(call echo,Ecere SDK Source Warning: The value of ECERE_SDK_SRC is pointing to an incorrect ($(ECERE_SDK_SRC)) location.)),)
	$(if $(ECERE_SDK_SRC),,$(if $(ECP_DEBUG)$(ECC_DEBUG)$(ECS_DEBUG),@$(call echo,ECC Debug Warning: Please define ECERE_SDK_SRC before using ECP_DEBUG, ECC_DEBUG or ECS_DEBUG),))

$(OBJ)$(MODULE).main.ec: $(SYMBOLS) $(COBJECTS)
	@$(call rm,$(OBJ)symbols.lst)
	@$(call touch,$(OBJ)symbols.lst)
	$(call addtolistfile,$(SYMBOLS),$(OBJ)symbols.lst)
	$(call addtolistfile,$(IMPORTS),$(OBJ)symbols.lst)
	$(ECS) $(ARCH_FLAGS) $(ECSLIBOPT) @$(OBJ)symbols.lst -symbols obj/$(CONFIG).$(PLATFORM)$(COMPILER_SUFFIX)$(DEBUG_SUFFIX) -o $(call quote_path,$@)

$(OBJ)$(MODULE).main.c: $(OBJ)$(MODULE).main.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(OBJ)$(MODULE).main.ec -o $(OBJ)$(MODULE).main.sym -symbols $(OBJ)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(OBJ)$(MODULE).main.ec -o $(call quote_path,$@) -symbols $(OBJ)

$(SYMBOLS): | objdir
$(OBJECTS): | objdir
$(TARGET): $(SOURCES) $(RESOURCES_EAR) $(SYMBOLS) $(OBJECTS) | objdir
	@$(call rm,$(OBJ)objects.lst)
	@$(call touch,$(OBJ)objects.lst)
	$(call addtolistfile,$(OBJ)$(MODULE).main$(O),$(OBJ)objects.lst)
	$(call addtolistfile,$(ECOBJECTS),$(OBJ)objects.lst)
ifndef STATIC_LIBRARY_TARGET
	$(LD) $(OFLAGS) @$(OBJ)objects.lst $(LIBS) -o $(TARGET) $(INSTALLNAME) $(SONAME)
ifndef NOSTRIP
	$(STRIP) $(STRIPOPT) $(TARGET)
endif
else
ifdef WINDOWS_HOST
	$(AR) rcs $(TARGET) @$(OBJ)objects.lst $(LIBS)
else
	$(AR) rcs $(TARGET) $(OBJECTS) $(LIBS)
endif
endif
ifdef SHARED_LIBRARY_TARGET
ifdef LINUX_TARGET
ifdef LINUX_HOST
	$(if $(basename $(basename $(VER))),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(OBJ)$(LP)$(MODULE)$(SO)$(basename $(basename $(VER))),)
	$(if $(basename $(VER)),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(OBJ)$(LP)$(MODULE)$(SO)$(basename $(VER)),)
	$(if $(VER),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(OBJ)$(LP)$(MODULE)$(SO),)
endif
endif
endif
	$(call mkdir,$(SOCKETS_ABSPATH)/$(SODESTDIR))
	$(call cp,$(TARGET),$(SOCKETS_ABSPATH)/$(SODESTDIR))
ifdef LINUX_TARGET
	$(if $(basename $(basename $(VER))),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(SOCKETS_ABSPATH)/$(SODESTDIR)$(LP)$(MODULE)$(SO)$(basename $(basename $(VER))),)
	$(if $(basename $(VER)),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(SOCKETS_ABSPATH)/$(SODESTDIR)$(LP)$(MODULE)$(SO)$(basename $(VER)),)
	$(if $(VER),ln -sf $(LP)$(MODULE)$(SO)$(VER) $(SOCKETS_ABSPATH)/$(SODESTDIR)$(LP)$(MODULE)$(SO),)
endif

# SYMBOL RULES

$(OBJ)network.sym: network.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,network.ec) -o $(call quote_path,$@)

$(OBJ)Service.sym: Service.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,Service.ec) -o $(call quote_path,$@)

$(OBJ)Socket.sym: Socket.ec
	$(ECP) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) -c $(call quote_path,Socket.ec) -o $(call quote_path,$@)

# C OBJECT RULES

$(OBJ)network.c: network.ec $(OBJ)network.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,network.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)Service.c: Service.ec $(OBJ)Service.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,Service.ec) -o $(call quote_path,$@) -symbols $(OBJ)

$(OBJ)Socket.c: Socket.ec $(OBJ)Socket.sym | $(SYMBOLS)
	$(ECC) $(CFLAGS) $(CECFLAGS) $(ECFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,Socket.ec) -o $(call quote_path,$@) -symbols $(OBJ)

# OBJECT RULES

$(OBJ)network$(O): $(OBJ)network.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)network.c) -o $(call quote_path,$@)

$(OBJ)Service$(O): $(OBJ)Service.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Service.c) -o $(call quote_path,$@)

$(OBJ)Socket$(O): $(OBJ)Socket.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(call quote_path,$(OBJ)Socket.c) -o $(call quote_path,$@)

$(OBJ)$(MODULE).main$(O): $(OBJ)$(MODULE).main.c
	$(CC) $(CFLAGS) $(PRJ_CFLAGS) $(FVISIBILITY) -c $(OBJ)$(MODULE).main.c -o $(call quote_path,$@)

cleantarget:
	$(call rm,$(OBJ)$(MODULE).main$(O) $(OBJ)$(MODULE).main.c $(OBJ)$(MODULE).main.ec $(OBJ)$(MODULE).main$(I) $(OBJ)$(MODULE).main$(S))
	$(call rm,$(OBJ)symbols.lst)
	$(call rm,$(OBJ)objects.lst)
	$(call rm,$(TARGET))
ifdef SHARED_LIBRARY_TARGET
ifdef LINUX_TARGET
ifdef LINUX_HOST
	$(call rm,$(OBJ)$(LP)$(MODULE)$(SO)$(basename $(basename $(VER))))
	$(call rm,$(OBJ)$(LP)$(MODULE)$(SO)$(basename $(VER)))
	$(call rm,$(OBJ)$(LP)$(MODULE)$(SO))
endif
endif
endif

clean: cleantarget
	$(call rm,$(_OBJECTS))
	$(call rm,$(_ECOBJECTS))
	$(call rm,$(_COBJECTS))
	$(call rm,$(_BOWLS))
	$(call rm,$(_IMPORTS))
	$(call rm,$(_SYMBOLS))

realclean: cleantarget
	$(call rmr,$(OBJ))

distclean: cleantarget
	$(call rmr,obj/)
	$(call rmr,.configs/)
	$(call rm,*.ews)
	$(call rm,*.Makefile)
