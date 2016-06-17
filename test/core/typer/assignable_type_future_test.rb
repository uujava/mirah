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
require 'test_helper'

class TypeFutureTest < Test::Unit::TestCase
  include Mirah
  include Mirah::Util::ProcessErrors
  java_import 'org.mirah.typer.TypeFuture'
  java_import 'org.mirah.typer.AssignableTypeFuture'
  java_import 'org.mirah.typer.SimpleScoper'
  java_import 'org.mirah.typer.ErrorType'
  java_import 'org.mirah.typer.BaseTypeFuture'
  java_import 'mirah.lang.ast.VCall'
  java_import 'mirah.lang.ast.FunctionalCall'
  java_import 'mirah.lang.ast.PositionImpl'
  java_import 'mirah.lang.ast.LocalAccess'
  java_import 'mirah.objectweb.asm.Type'
  java_import 'org.mirah.jvm.mirrors.MirrorTypeSystem'
  java_import 'org.mirah.jvm.mirrors.ClassLoaderResourceLoader'
  java_import 'org.mirah.jvm.mirrors.ClassResourceLoader'
  java_import 'org.mirah.IsolatedResourceLoader'

  module TypeFuture
    def inspect
      toString
    end
  end
  
  POS = PositionImpl.new(nil, 0, 0, 0, 0, 0, 0)

  def setup
    class_based_loader = ClassResourceLoader.new(MirrorTypeSystem.java_class)
    loader = ClassLoaderResourceLoader.new(
        IsolatedResourceLoader.new([TEST_DEST,FIXTURE_TEST_DEST].map{|u|java.net.URL.new "file:"+u}),
        class_based_loader)
    @types = MirrorTypeSystem.new nil, loader
  end

  def load(desc)
    @types.wrap(desc).resolve
  end

  def test_assignable_future_when_declared_resolves_to_declared_type
    future = AssignableTypeFuture.new POS
    type = load(Type.getType("Ljava/lang/Object;"))
    r_future = BaseTypeFuture.new
    r_future.resolved(type)
    future.declare r_future, POS
    assert_equal type, future.resolve, "Expected #{future.resolve} to be a #{type}"
  end


  def test_assignable_future_doesnt_allow_multiple_declarations_of_different_types
    future = AssignableTypeFuture.new POS
    type = load(Type.getType("Ljava/lang/Object;"))
    obj_future = BaseTypeFuture.new
    obj_future.resolved(type)
    type = load(Type.getType("LNotObject;"))
    not_obj_future = BaseTypeFuture.new
    not_obj_future.resolved(type)

    future.declare obj_future, POS
    future.declare not_obj_future, POS

    assign_future = future.assign obj_future, POS

    assert_kind_of ErrorType, assign_future.resolve
  end

  def test_assignable_future_doesnt_allow_invalid_assignment_to_declared_type
    future = AssignableTypeFuture.new POS
    type = load(Type.getType("Ljava/lang/Object;"))
    obj_future = BaseTypeFuture.new
    obj_future.resolved(type)

    future.declare obj_future, POS

    type = load(Type.getType("LNotObject;"))
    not_obj_future = BaseTypeFuture.new
    not_obj_future.resolved(type)

    assignment_future = future.assign not_obj_future, POS
    
    assert_kind_of ErrorType, assignment_future.resolve
  end
end