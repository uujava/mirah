# Copyright (c) 2012-2016 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

package org.mirah.jvm.compiler

import java.io.File
import java.util.Collections
import java.util.List
import java.util.LinkedList
import java.util.HashSet
import java.util.Set
import org.mirah.util.Logger
import mirah.lang.ast.*
import org.mirah.util.Context
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.types.JVMTypeUtils
import org.mirah.jvm.mirrors.Member
import org.mirah.jvm.mirrors.MirrorType
import org.mirah.jvm.mirrors.MacroMember

import mirah.objectweb.asm.ClassWriter
import mirah.objectweb.asm.Opcodes
import mirah.objectweb.asm.commons.Method

class ClassCompiler < BaseCompiler implements InnerClassCompiler
  def self.initialize:void
    @@log = Logger.getLogger(ClassCompiler.class.getName)
  end
  def initialize(context:Context, classdef:ClassDefinition)
    super(context)
    @classdef = classdef
    @fields = {}
    @innerClasses = LinkedList.new
    @type = getInferredType(@classdef)
  end
  def initialize(context:Context, classdef:ClassDefinition, outerClass:JVMType, method:Method)
    initialize(context, classdef)
    @outerClass = outerClass
    @enclosingMethod = method
  end  
  
  def compile:void
    @@log.fine "Compiling class #{@classdef.name.identifier}"
    startClass
    visit(@classdef.body, nil)
    @classwriter.visitEnd
    @@log.fine "Finished class #{@classdef.name.identifier}"
  end

  def getInternalName(type:JVMType)
    type.getAsmType.getInternalName
  end

  def visitClassAppendSelf(node, expression)
    saved = @static
    @static = true
    visit(node.body, expression)
    @static = saved
    nil
  end
  
  def visitMethodDefinition(node, expression)
    isStatic = @static || node.kind_of?(StaticMethodDefinition)
    constructor = isStatic && "initialize".equals(node.name.identifier)
    name = constructor ? "<clinit>" : node.name.identifier.replaceFirst("=$", "_set")
    method = MethodCompiler.new(self, @type, methodFlags(node, isStatic), name)
    method.compile(@classwriter, node)
  end
  
  def visitStaticMethodDefinition(node, expression)
    visitMethodDefinition(node, expression)
  end
  
  def visitConstructorDefinition(node, expression)
    method = MethodCompiler.new(self, @type, Opcodes.ACC_PUBLIC, "<init>")
    method.compile(@classwriter, node)
  end
  
  def visitClassDefinition(node, expression)
    compileInnerClass(node, nil)
  end
  
  def visitInterfaceDeclaration(node, expression)
    compileInnerInterface(node, nil)
  end
  
  def compileInnerClass(node:ClassDefinition, method:Method):void
    compiler = ClassCompiler.new(context, node, @type, method)
    # TODO only supporting anonymous inner classes for now.
    @classwriter.visitInnerClass(compiler.internal_name, nil, nil, 0)
    compiler.compile
    addInnerClass(compiler)
  end

  def compileInnerInterface(node:InterfaceDeclaration, method:Method):void
    compiler = InterfaceCompiler.new(context, node, @type, method)
    # TODO only supporting anonymous inner classes for now.
    @classwriter.visitInnerClass(compiler.internal_name, nil, nil, 0)
    compiler.compile
    addInnerClass(compiler)
  end

  def addInnerClass(compiler)
    @innerClasses.add(compiler)
  end

  def getBytes:byte[]
    # TODO CheckClassAdapter
    @classwriter.toByteArray
  end
  
  def startClass:void
    # TODO: need to support widening before we use COMPUTE_FRAMES
    jvm = context[JvmVersion]
    @classwriter = MirahClassWriter.new(context, jvm.flags)
    @classwriter.visit(jvm.version, flags, internal_name, nil, superclass, interfaces)
    filename = self.filename
    @classwriter.visitSource(filename, nil) if filename
    if @outerClass
      method = @enclosingMethod.getName if @enclosingMethod
      desc = @enclosingMethod.getDescriptor if @enclosingMethod
      @classwriter.visitOuterClass(getInternalName(@outerClass), method, desc)
    end
    context[AnnotationCompiler].compile(@classdef.annotations, @classwriter)
  end
  
  def visitFieldDeclaration(node, expression)
    flags = JVMTypeUtils.calculateFlags(Opcodes.ACC_PRIVATE, node)
    flags |=Opcodes.ACC_STATIC if node.isStatic
    fv = @classwriter.visitField(flags, node.name.identifier, getInferredType(node).getAsmType.getDescriptor, nil, nil)
    context[AnnotationCompiler].compile(node.annotations, fv)
    fv.visitEnd
  end
  
  def flags
    JVMTypeUtils.calculateFlags(Opcodes.ACC_PUBLIC, @classdef) | Opcodes.ACC_SUPER
  end
  
  def methodFlags(mdef:MethodDefinition, isStatic:boolean)
    flags = JVMTypeUtils.calculateFlags(Opcodes.ACC_PUBLIC, mdef)
    if isStatic
      flags | Opcodes.ACC_STATIC
    else
      flags
    end
  end
  
  def internal_name
    getInternalName(@type)
  end
  
  def filename
    if @classdef.position
      path = @classdef.position.source.name
      lastslash = path.lastIndexOf(File.separatorChar)
      if lastslash == -1
        return path
      else
        return path.substring(lastslash + 1)
      end
    end
    nil
  end
  
  def superclass
    getInternalName(@type.superclass) if @type.superclass
  end
  
  def interfaces
    size = @classdef.interfaces.size
    array = String[size]
    i = 0
    size.times do |i|
      node = @classdef.interfaces.get(i)
      array[i] = getInternalName(getInferredType(node))
    end
    array
  end
  
  def innerClasses
    Collections.unmodifiableCollection(@innerClasses)
  end

  protected def verify
    return if JVMTypeUtils.isAbstract(@type)
    # naive check all abstract methods implemented
    abstract_methods = HashSet.new
    impl_methods = HashSet.new
    # TODO does this check cover bridge, synthetic and generic methods properly???
    type = @type:MirrorType
    collect_methods(type.getAllDeclaredMethods, abstract_methods, impl_methods)
    collect_super_methods(type, abstract_methods, impl_methods)
    @@log.fine "#{@type} abstract signatures: #{abstract_methods}"
    @@log.fine "#{@type} implemented signatures: #{impl_methods}"
    abstract_methods.removeAll(impl_methods) if abstract_methods.size > 0

    if abstract_methods.size > 0
      raise VerifyError.new("Abstract methods not implemented for not abstract class #{@type}:\n#{get_methods_spec(abstract_methods)}")
    end
  end

  private def self.collect_super_methods(type:MirrorType, abstract_methods:Set, impl_methods:Set):void
    type.directSupertypes.each do |super_type: MirrorType|
      collect_methods(super_type.getAllDeclaredMethods, abstract_methods, impl_methods)
      collect_super_methods(super_type, abstract_methods, impl_methods)
    end
  end

  private def self.collect_methods(members: List, abstract_methods:Set, impl_methods:Set):void
    members.each do |member: Member|
      next if member.kind_of? MacroMember
      next if JVMTypeUtils.isStatic(member)
      spec = [member.name, member.argumentTypes, member.returnType.toString]
      if member.isAbstract
        abstract_methods << spec
      else
        impl_methods << spec
      end
    end
  end

  private def get_methods_spec(list:Set):String
    sb = StringBuilder.new
    list.each do |data:List|
      sb.append(data[0]).append('(')
      data[1]:List.each_with_index do |arg, j|
        sb.append (',') unless j == 0
        sb.append arg
      end
      sb.append('):').append(data[2])
      sb.append(';').append("\n")
    end
    sb.toString
  end
end