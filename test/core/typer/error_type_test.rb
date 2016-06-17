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

class ErrorTypeTest < Test::Unit::TestCase
    include Mirah
  include Mirah::Util::ProcessErrors
  java_import 'org.mirah.typer.TypeFuture'
  java_import 'org.mirah.typer.AssignableTypeFuture'
  java_import 'org.mirah.typer.SimpleScoper'
  java_import 'org.mirah.typer.ErrorType'
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

  def test_error_type_matches_anything
    type = ErrorType.new [["",POS]]
    assert type.matchesAnything, "errors match any type"
  end

  def test_error_type_is_not_assignable_from
    type = ErrorType.new [["",POS]]
    assert !type.assignableFrom(load(Type.getType("Ljava/lang/Object;")))
  end

  def test_error_type_equal_to_another_error_type_when_message_same
    type = ErrorType.new [["message one",POS]]
    type2 = ErrorType.new [["message one",POS]]
    assert_equal type, type2
  end

  def test_error_type_not_equal_to_another_error_type_when_message_differs
    type = ErrorType.new [["message one",POS]]
    type2 = ErrorType.new [["message two",POS]]
    assert_not_equal type, type2
  end
end