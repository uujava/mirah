# Copyright (c) 2012 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.model

import java.util.Arrays
import java.util.ArrayList
import java.util.EnumMap
import javax.lang.model.element.TypeElement as ITypeElement
#import javax.lang.model.type.ArrayType
import javax.lang.model.type.DeclaredType
#import javax.lang.model.type.NoType
#import javax.lang.model.type.NullType
import org.mirah.jvm.mirrors.NullType
import org.mirah.jvm.mirrors.NumberType
import org.mirah.jvm.mirrors.VoidType
import org.mirah.jvm.mirrors.ArrayType
import javax.lang.model.type.PrimitiveType
import javax.lang.model.type.TypeVariable as TypeVariableModel
import javax.lang.model.type.TypeKind
import javax.lang.model.type.TypeMirror
import javax.lang.model.type.WildcardType
import javax.lang.model.util.SimpleTypeVisitor6
import javax.lang.model.util.Types as TypesModel
import mirah.objectweb.asm.Type
import org.mirah.jvm.mirrors.BaseType
import org.mirah.jvm.mirrors.MirrorType
import org.mirah.jvm.mirrors.DeclaredMirrorType
import org.mirah.jvm.mirrors.MirrorTypeSystem
import org.mirah.jvm.mirrors.generics.TypeInvocation
import org.mirah.jvm.mirrors.generics.Wildcard
import org.mirah.jvm.model.IntersectionType
import org.mirah.jvm.types.JVMTypeUtils
import org.mirah.typer.BaseTypeFuture
import org.mirah.typer.TypeFuture
import org.mirah.util.Context

class Types implements TypesModel
  def initialize(context:Context)
    @emptyWildcard = Wildcard.new(@context,@object,nil,nil)
    @context = context
    @types = context[MirrorTypeSystem]
    context[TypesModel] = self
    @object:MirrorType = @types.loadNamedType('java.lang.Object').resolve
    @primitives = EnumMap.new(
      TypeKind.BOOLEAN => @types.loadNamedType('boolean').resolve,
      TypeKind.BYTE => @types.loadNamedType('byte').resolve,
      TypeKind.CHAR => @types.loadNamedType('char').resolve,
      TypeKind.DOUBLE => @types.loadNamedType('double').resolve,
      TypeKind.FLOAT => @types.loadNamedType('float').resolve,
      TypeKind.INT => @types.loadNamedType('int').resolve,
      TypeKind.LONG => @types.loadNamedType('long').resolve,
      TypeKind.SHORT => @types.loadNamedType('short').resolve
    )
  end

  def boxedClass(p)
    TypeElement.new(p:NumberType.box:MirrorType)
  end

  def getArrayType(component)
    @types.getResolvedArrayType(component:MirrorType):ArrayType
  end

  def getNoType(kind)
    if kind == TypeKind.VOID
      return @types.getVoidType.resolve:VoidType
    end
  end

  def getNullType
    @types.getNullType.resolve:NullType
  end

  def getPrimitiveType(kind)
    @primitives[kind]:PrimitiveType
  end

  def directSupertypes(t)
    t:MirrorType.directSupertypes
  end

  def asElement(t)
    TypeElement.new(t:MirrorType)
  end

  def erasure(x)
    x:MirrorType.erasure
  end

  def isSameType(a, b)
    a:MirrorType.isSameType(b:MirrorType)
  end

  def isSubtype(a, b)
    b:MirrorType.isSupertypeOf(a:MirrorType)
  end

  def getDeclaredType(element:ITypeElement, args:TypeMirror[]):DeclaredType
    t = Type.getType(element:TypeElement.descriptor)
    type = @types.wrap(t)
    arg_futures = ArrayList.new(args.length)
    args.each do |arg|
      arg_futures.add(BaseTypeFuture.new.resolved(arg:MirrorType))
    end
    @types.parameterize(type, arg_futures).resolve:DeclaredMirrorType
  end

  def getWildcardType(extendsBound, superBound)
    return @emptyWildcard if extendsBound.nil? && superBound.nil?

    Wildcard.new(@context, @object, extendsBound, superBound)
  end
end