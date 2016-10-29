# Copyright (c) 2016 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.compiler.casesupport

import mirah.objectweb.asm.Label
import mirah.objectweb.asm.Type
import mirah.objectweb.asm.commons.Method
import static mirah.objectweb.asm.Opcodes.*
import mirah.objectweb.asm.ClassWriter
import mirah.objectweb.asm.MethodVisitor
import mirah.objectweb.asm.commons.TableSwitchGenerator
import mirah.lang.ast.Node
import mirah.lang.ast.NodeList
import mirah.lang.ast.Case
import mirah.lang.ast.WhenClause
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.compiler.MethodCompiler
import org.mirah.jvm.compiler.Bytecode
import org.mirah.jvm.compiler.JvmVersion
import org.mirah.jvm.compiler.BaseCompiler
import org.mirah.jvm.compiler.BytecodeConsumer
import org.mirah.jvm.compiler.InnerClassCompiler
import java.util.List
import java.util.Arrays
import java.util.Collections

class EnumSwitchCompiler implements TableSwitchCompiler, InnerClassCompiler

  def initialize(method:MethodCompiler, targetType:JVMType, conditionType:JVMType, builder: Bytecode, keys:List, defaultBody:NodeList)
    @method = method
    @builder = builder
    @targetType = targetType
    @conditionType = conditionType
    @defaultBody = defaultBody
    @keys = int[keys.size]
    @bodies = NodeList[@keys.size + 1] # keys are numbered from 1 - need 0 to be empty

    @enums = EnumValue[keys.size]
    keys.each_with_index do |key_data:List, i:int|
      key = key_data[0]:EnumValue
      @enums[i] = key
      @keys[i] = i+1 # keys numbered from 1 to keys.size
      @bodies[i+1] = key_data[2] # when body
    end
    initConstants
  end


  def compile(node:Case, expression:Object):void
    # generate constant array for lookup also fill:
    # @innerName
    # @fieldName - constant name to lookup key by enum order
    generateOrderMapping(@enums)

    @builder.getStatic(Type.getType("L#{@innerName};"), @fieldName, Type.getType('[I'))
    @method.visit(node.condition, Boolean.TRUE)
    @builder.invokeVirtual(@conditionType.getAsmType, @@ordinal)
    @builder.arrayLoad(@@int.getAsmType)
    @builder.tableSwitch(@keys, BodyGenerator.new(@method, @builder, @bodies, @defaultBody, @targetType, expression), true)
  end

  def initConstants:void
    unless @@int
      @@int = @method.findType("int")
      @@ordinal = Method.new('ordinal', '()I')
      @@catchEx = "java/lang/NoSuchFieldError"
    end
  end

  # reverse engineered behaviour
  # this synthetic class is unique and do not leak outside of the method
  # it's faster to generate bytecode without an ast
  def generateOrderMapping(enums: EnumValue[])
    cw = ClassWriter.new ASM5
    outerName =  @method.selfType.getAsmType.getInternalName
    @innerName =  @method.selfScope.temp('Case')
    @innerName = "#{outerName}$#{@innerName}".replace ',', '/'
    enumName = enums.first.type.name.replace '.', '/'
    enumDescriptor = "L#{enumName};"

    catchFrameEx = Object[1]
    catchFrameEx[0] = @@catchEx
    @fieldName = "$SwitchMap$#{enumName.replace('/','$')}"

    cw.visit(@method.context[JvmVersion].bytecode_version, ACC_SUPER | ACC_SYNTHETIC, innerName, nil, 'java/lang/Object', nil)

    cw.visitOuterClass(outerName, nil, nil)
    cw.visitInnerClass(@innerName, nil, nil, ACC_STATIC | ACC_SYNTHETIC)

    fv = cw.visitField(ACC_FINAL | ACC_STATIC | ACC_SYNTHETIC, @fieldName, "[I", nil, nil)
    fv.visitEnd
    # create static int array storing map from order number to case id

    mv = cw.visitMethod(ACC_STATIC, "<clinit>", "()V", nil, nil)

    mv.visitCode
    mv.visitMethodInsn(INVOKESTATIC, enumName, "values", "()[#{enumDescriptor}", false)
    mv.visitInsn(ARRAYLENGTH)
    # array filled with 0
    mv.visitIntInsn(NEWARRAY, T_INT)

    mv.visitFieldInsn(PUTSTATIC, innerName, @fieldName, "[I")

    b_next = Label.new
    b_start = Label.new

    enums.each_with_index do |v, i|
      b_end = Label.new
      b_catch = Label.new
      mv.visitTryCatchBlock(b_start, b_end, b_catch, @@catchEx)

      mv.visitLabel(b_start)
      mv.visitFieldInsn(GETSTATIC, innerName, @fieldName, "[I")
      mv.visitFieldInsn(GETSTATIC, enumName, v.name, enumDescriptor)
      mv.visitMethodInsn(INVOKEVIRTUAL, enumName, "ordinal", "()I", false)
      # keys in tables switch stated with 1
      push(mv, i + 1)
      mv.visitInsn IASTORE
      mv.visitLabel(b_end)
      mv.visitJumpInsn(GOTO, b_next)
      mv.visitLabel(b_catch)
      mv.visitFrame(F_SAME1, 0, nil, 1, catchFrameEx)
      mv.visitVarInsn(ASTORE, 0)

      mv.visitLabel(b_next)
      mv.visitFrame(F_SAME, 0, nil, 0, nil)
      b_start = b_next
      b_next = Label.new
    end

    mv.visitInsn RETURN
    mv.visitMaxs 3, 1
    mv.visitEnd
    cw.visitEnd
    @bytes = cw.toByteArray();

    # it's a time to add generated class for later BytecodeConsumer handling
    @method.addInnerClass(self)
  end

  def push(mv:MethodVisitor, value:int):void
    if value >= -1 && value <= 5
      mv.visitInsn ICONST_0 + value
    elsif value >= Byte.MIN_VALUE && value <= Byte.MAX_VALUE
      mv.visitIntInsn BIPUSH, value
    elsif value >= Short.MIN_VALUE && value <= Short.MAX_VALUE
      mv.visitIntInsn SIPUSH, value
    else
      mv.visitLdcInsn(value:Integer)
    end
  end

  # InnerClassCompiler implementation
  def context
    raise "Unsupported operation exception"
  end

  def compileInnerClass(node, method):void
    raise "Unsupported operation exception"
  end
  # add inner compiler
  def addInnerClass(compiler:InnerClassCompiler):void
    raise "Unsupported operation exception"
  end

  # @return Enum Constant support class
  def internal_name:String
    @innerName
  end

  # Class data byte array
  def getBytes:byte[]
    @bytes
  end

  # Collection of InnerClassesCompilers generated implicitly by this class compiler
  def innerClasses
    Collections.emptyList
  end


end