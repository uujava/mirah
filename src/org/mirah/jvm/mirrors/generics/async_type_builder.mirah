# Copyright (c) 2013 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.mirrors.generics

import java.util.Map
import javax.lang.model.element.TypeElement
import javax.lang.model.type.DeclaredType
import javax.lang.model.type.TypeMirror
import javax.lang.model.util.Types
import mirah.objectweb.asm.Opcodes
import mirah.objectweb.asm.Type
import mirah.objectweb.asm.signature.SignatureVisitor
import org.mirah.jvm.mirrors.MirrorTypeSystem
import org.mirah.jvm.mirrors.MirrorType
import org.mirah.jvm.mirrors.generics.Wildcard
import org.mirah.typer.BaseTypeFuture
import org.mirah.typer.DerivedFuture
import org.mirah.typer.TypeFuture
import org.mirah.util.Context


interface AsyncTypeBuilderResult
  def getResult:TypeFuture; end
end

class AsyncTypeBuilder < SignatureVisitor
  def initialize(context:Context, typeVariables:Map, processed_signatures:Map):void
    super(Opcodes.ASM5)
    @context = context
    @typeVariables = typeVariables
    @types = @context[MirrorTypeSystem]
    @type_utils = @context[Types]
    @processed_signatures = processed_signatures
  end

  def visitBaseType(desc)
    @type = @types.wrap(Type.getType("#{desc}"))
  end

  def visitTypeVariable(name)
    @type = @typeVariables[name]:TypeFuture
  end

  def visitArrayType
    component = newBuilder
    types = @types
    @result = lambda(AsyncTypeBuilderResult) do
      f = component.future # f can be nil, as it may refer to a type variable intentionally not defined in TypeInvoker
      f ? types.getArrayType(f) : nil
    end
    component
  end

  def visitClassType(name)
    @type = @types.wrap(Type.getType("L#{name};"))
    @class_name = name
    @typeArguments = []
  end

  def visitTypeArgument
    @typeArguments.add(BaseTypeFuture.new.resolved(
        @type_utils.getWildcardType(nil, nil):Wildcard))
  end

  def visitTypeArgument(kind)
    builder = newBuilder
    utils = @type_utils
    @typeArguments.add(lambda(AsyncTypeBuilderResult) do
      if builder.future
        DerivedFuture.new(builder.future) do |resolved|
          type = resolved:MirrorType
          if kind == ?=
            type
          elsif kind == ?-
            utils.getWildcardType(type, nil):Wildcard
          else
            utils.getWildcardType(nil, type):Wildcard
          end
        end
      else
        nil
      end
    end)
    builder
  end

  def visitInnerClassType(name)
    @outer = @type
    @typeArguments = []
    @class_name = "#{@class_name}$#{name}"
    @type = @types.wrap(Type.getType("L#{@class_name};"))
  end

  def visitEnd: void
    return if @outer.nil? && @typeArguments.isEmpty

    # TODO: handle inner types properly
    args = @typeArguments.map do |a|
      if a.kind_of?(AsyncTypeBuilderResult)
        a:AsyncTypeBuilderResult.getResult
      else
        a
      end
    end
    utils = @type_utils
    #TODO use {|ar: TypeFuture| !ar || utils.getWildcardType(nil, nil):MirrorType.equals(ar.resolve) }
    # once the parser is fixed to support it
    all_question_marks=args.all? do |ar: TypeFuture|
      if ar
        utils.getWildcardType(nil, nil):Wildcard.equals(ar.resolve)
      else
        true
      end
    end
    return if all_question_marks
    @type = @types.parameterize(@type, args, @processed_signatures)
  end

  def newBuilder
    AsyncTypeBuilder.new(@context, @typeVariables, @processed_signatures)
  end

  def future
    if @type
      @type
    elsif @result
      @type = @result.getResult
    else
      nil
    end
  end
end