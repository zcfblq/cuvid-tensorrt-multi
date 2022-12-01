cc        := g++
short_name:= pro
name      := lib$(short_name).so
example   := example
workdir   := workspace
srcdir    := src
exampledir:= examples
objdir    := objs
stdcpp    := c++14
cuda_home := /usr/local/cuda
cpp_pkg   := /cangku_workspace/repos/hard_decode_trt_multicamera/third_party
syslib    := 
cuda_arch := 

# 定义cpp的路径查找和依赖项mk文件
cpp_srcs := $(shell find $(srcdir) -name "*.cpp")
cpp_objs := $(cpp_srcs:.cpp=.cpp.o)
cpp_objs := $(cpp_objs:$(srcdir)/%=$(objdir)/%)
cpp_mk   := $(cpp_objs:.cpp.o=.cpp.mk)

cpp_srcs_example := $(shell find $(exampledir) -name "*.cpp")
cpp_objs_example := $(cpp_srcs_example:.cpp=.cpp.o)
cpp_objs_example := $(cpp_objs_example:$(exampledir)/%=$(objdir)/%)
cpp_mk_example   := $(cpp_objs_example:.cpp.o=.cpp.mk)

# 定义cu文件的路径查找和依赖项mk文件
cu_srcs := $(shell find $(srcdir) -name "*.cu")
cu_objs := $(cu_srcs:.cu=.cu.o)
cu_objs := $(cu_objs:$(srcdir)/%=$(objdir)/%)
cu_mk   := $(cu_objs:.cu.o=.cu.mk)

# 定义opencv和cuda需要用到的库文件
link_opencv    := opencv_core opencv_imgproc opencv_imgcodecs opencv_videoio
link_cuda      := cuda cudart cudnn nvcuvid nvidia-encode
link_ffmpeg    := avcodec avformat swresample swscale avutil
link_tensorRT  := nvinfer nvparsers nvinfer_plugin protobuf
link_sys       := stdc++ dl
link_librarys  := $(link_opencv) $(link_cuda) $(link_tensorRT) $(link_sys) $(link_ffmpeg)

# 定义cuda和opencv的库路径
nvcc              := $(cuda_home)/bin/nvcc -ccbin=$(cc)
include_cuda      := $(cuda_home)/include
include_tensorRT  := 
include_protobuf  := $(cpp_pkg)/protobuf/include
include_cuvid     := $(cpp_pkg)/cuvid/include
include_opencv    := /usr/local/include/opencv4

lib_all        := $(cuda_home)/lib64 $(cpp_pkg)/protobuf/lib $(syslib) /lib/x86_64-linux-gnu

# 定义头文件路径，请注意斜杠后边不能有空格
# 只需要写路径，不需要写-I
include_paths := src    \
    $(include_cuda)     \
	$(include_tensorRT) \
	$(include_protobuf) \
	$(include_opencv)   \
	src/tensorRT        \
	src/tensorRT/common \
	src/application     \
	src/application/track     \
	$(include_cuvid)       

# 定义库文件路径，只需要写路径，不需要写-L
library_paths := $(lib_all)

# 把library path给拼接为一个字符串，例如a b c => a:b:c
# 然后使得LD_LIBRARY_PATH=a:b:c
empty := 
library_path_export := $(subst $(empty) $(empty),:,$(library_paths))

# 把库路径和头文件路径拼接起来成一个，批量自动加-I、-L、-l
run_paths     := $(foreach item,$(library_paths),-Wl,-rpath=$(item))
include_paths := $(foreach item,$(include_paths),-I$(item))
library_paths := $(foreach item,$(library_paths),-L$(item))
link_librarys := $(foreach item,$(link_librarys),-l$(item))

# 如果是其他显卡，请修改-gencode=arch=compute_75,code=sm_75为对应显卡的能力
# 显卡对应的号码参考这里：https://developer.nvidia.com/zh-cn/cuda-gpus#compute
# 如果是 jetson nano，提示找不到-m64指令，请删掉 -m64选项。不影响结果
cpp_compile_flags := -std=$(stdcpp) -w -g -O0 -m64 -fPIC -fopenmp -pthread
cu_compile_flags  := -std=$(stdcpp) -w -g -O0 -m64 $(cuda_arch) -Xcompiler "$(cpp_compile_flags)"
link_flags        := -pthread -fopenmp -Wl,-rpath='$$ORIGIN'

cpp_compile_flags += $(include_paths)
cu_compile_flags  += $(include_paths)
link_flags        += $(library_paths) $(link_librarys) $(run_paths)

# 如果头文件修改了，这里的指令可以让他自动编译依赖的cpp或者cu文件
ifneq ($(MAKECMDGOALS), clean)
-include $(cpp_mk) $(cu_mk) $(cpp_mk_example)
endif

$(name)   : $(workdir)/$(name)
$(example): $(workdir)/$(example)
$(example): $(name)

all       : $(name)
	@echo $(library_path_export) && echo $(link_librarys)
run       : $(example)
	@cd $(workdir) && ./$(example) yolo

yolo       : $(example)
	@cd $(workdir) && ./$(example) yolo

plate      : $(example)
	@cd $(workdir) && ./$(example) plate

yolopose   : $(example)
	@cd $(workdir) && ./$(example) yolopose

demuxer   : $(example)
	@cd $(workdir) && ./$(example) demuxer

hard_decode : $(example)
	@cd $(workdir) && ./$(example) hard_decode

multi : $(example)
	@cd $(workdir) && ./$(example) multi

pipeline : $(example)
	@cd $(workdir) && ./$(example) pipeline

$(workdir)/$(name) : $(cpp_objs) $(cu_objs)
	@echo Link $@
	@mkdir -p $(dir $@)
	@$(cc) $^ -shared -o $@ $(link_flags)

$(workdir)/$(example) : $(cpp_objs_example)
	@echo Link $@
	@mkdir -p $(dir $@)
	@$(cc) $^ -o $@ $(link_flags) -L$(workdir) -l$(short_name) -lopencv_freetype

$(objdir)/%.cpp.o : $(srcdir)/%.cpp
	@echo Compile CXX $<
	@mkdir -p $(dir $@)
	@$(cc) -c $< -o $@ $(cpp_compile_flags)

$(objdir)/%.cpp.o : $(exampledir)/%.cpp
	@echo Compile CXX $<
	@mkdir -p $(dir $@)
	@$(cc) -c $< -o $@ $(cpp_compile_flags)

$(objdir)/%.cu.o : $(srcdir)/%.cu
	@echo Compile CUDA $<
	@mkdir -p $(dir $@)
	@$(nvcc) -c $< -o $@ $(cu_compile_flags)

# 编译cpp依赖项，生成mk文件
$(objdir)/%.cpp.mk : $(srcdir)/%.cpp
	@echo Compile depends C++ $<
	@mkdir -p $(dir $@)
	@$(cc) -M $< -MF $@ -MT $(@:.cpp.mk=.cpp.o) $(cpp_compile_flags)

# 编译cpp依赖项，生成mk文件
$(objdir)/%.cpp.mk : $(exampledir)/%.cpp
	@echo Compile depends C++ $<
	@mkdir -p $(dir $@)
	@$(cc) -M $< -MF $@ -MT $(@:.cpp.mk=.cpp.o) $(cpp_compile_flags)
    
# 编译cu文件的依赖项，生成cumk文件
$(objdir)/%.cu.mk : $(srcdir)/%.cu
	@echo Compile depends CUDA $<
	@mkdir -p $(dir $@)
	@$(nvcc) -M $< -MF $@ -MT $(@:.cu.mk=.cu.o) $(cu_compile_flags)

# 定义清理指令
clean :
	@rm -rf $(objdir) $(workdir)/$(name) $(workdir)/hard $(workdir)/imgs $(workdir)/soft

# 防止符号被当做文件
.PHONY : clean run $(name)

# 导出依赖库路径，使得能够运行起来
export LD_LIBRARY_PATH:=$(library_path_export)