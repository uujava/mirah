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

package org.mirah.jvm.compiler

import java.util.Collections
import java.util.List
import org.mirah.util.Logger
import javax.tools.DiagnosticListener
import mirah.lang.ast.*
import org.mirah.jvm.types.JVMType
import static org.mirah.jvm.types.JVMTypeUtils.*
import org.mirah.typer.Typer
import org.mirah.typer.MethodType
import org.mirah.macros.Compiler as MacroCompiler
import org.mirah.util.Context
import org.mirah.util.MirahDiagnostic

import java.util.ArrayList
import javax.tools.Diagnostic.Kind

# Moves class-level field and constant initialization into the constructors/static initializer.
# TODO: generate synthetic/bridge methods.
# TODO: check for errors like undefined abstract methods or duplicate methods
class ClassCleanup < NodeScanner
  def initialize(context:Context, klass:ClassDefinition)
    @context = context
    @typer = context[Typer]
    @parser = context[MacroCompiler]
    @klass = klass
    @static_init_nodes = ArrayList.new
    @init_nodes = ArrayList.new
    @constructors = ArrayList.new
    @type = @typer.getResolvedType(@klass):JVMType
    @field_collector = FieldCollector.new(context, @type)
    @field_annotation_requestss = {}
    @methods = ArrayList.new
    @method_states = {}
  end

  def self.initialize:void
    @@log = Logger.getLogger(ClassCleanup.class.getName)
  end

  def clean:void
    if !addCleanedAnnotation()
      return
    end
    scan(@klass.body, nil)
    unless @static_init_nodes.isEmpty
      if @cinit.nil?
        @cinit = @parser.quote { def self.initialize:void; end }
        @klass.body.add(@cinit)
        @typer.infer(@cinit, false)
      end
      nodes = NodeList.new
      @static_init_nodes.each do |node: Node|
        node.parent.removeChild(node)
        node.setParent(nil)  # TODO: ast bug
        nodes.add(node)
      end
      old_body = @cinit.body
      @cinit.body = nodes
      @cinit.body.add(old_body)
      @typer.infer(nodes, false)
    end
    if @constructors.isEmpty 
      add_default_constructor unless @klass.kind_of?(InterfaceDeclaration)
    end

    @init_nodes.each do |node:Node|
      node.parent.removeChild(node)
      node.setParent(nil)  # TODO: not sure do we still need this?
    end

    init = if @init_nodes.nil?
      nil
    else
      NodeList.new(@init_nodes)
    end
    cleanup = ConstructorCleanup.new(@context)
    @constructors.each do |n: ConstructorDefinition|
      cleanup.clean(n, init)
    end

    declareFields
    @methods.each do |m: MethodDefinition|
      addOptionalMethods(m)
    end
  end
  
  # Adds the org.mirah.jvm.compiler.Cleaned annotation to the class.
  # Returns true if the annotation was added, or false if it already exists.
  def addCleanedAnnotation:boolean
    @klass.annotations_size.times do |i|
      anno = @klass.annotations(i)
      if "org.mirah.jvm.compiler.Cleaned".equals(anno.type.typeref.name)
        return false
      end
    end
    @klass.annotations.add(Annotation.new(SimpleString.new("org.mirah.jvm.compiler.Cleaned"), Collections.emptyList))
    true
  end
  
  def add_default_constructor
    constructor = @parser.quote { def initialize; end }
    constructor.body.add(Super.new(constructor.position, Collections.emptyList, nil))
    @klass.body.add(constructor)
    @typer.infer(constructor)
    @constructors.add(constructor)
  end
  
  def makeTypeRef(type:JVMType):TypeRef
    # FIXME: there's no way to represent multi-dimensional arrays in a TypeRef
    TypeRefImpl.new(type.name, isArray(type), false, nil)
  end
  
  def declareFields:void
    return if @alreadyCleaned
    type = @type
    type.getDeclaredFields.each do |f|
      @@log.finest "creating field declaration for #{f.name}"
      name = f.name
      decl = FieldDeclaration.new(SimpleString.new(name), makeTypeRef(f.returnType), nil, Collections.emptyList)
      decl.isStatic = type.hasStaticField(f.name)
      decl.annotations = @field_collector.getAnnotations(name)
      decl.modifiers = @field_collector.getModifiers(name)
      @klass.body.add(decl)
      @typer.infer(decl)
    end
  end
  
  def error(message:String, position:Position)
    @context[DiagnosticListener].report(MirahDiagnostic.error(position, message))
  end

  def note(message:String, position:Position)
    @context[DiagnosticListener].report(MirahDiagnostic.note(position, message))
  end

  def addMethodState(state:MethodState):void
    methods = @method_states[state.name]:List
    methods ||= @method_states[state.name] = []
    methods.each do |m:MethodState|
      conflict = m.conflictsWith(state)
      if conflict
        desc = if conflict == Kind.ERROR
          "Conflicting definition of #{state}"
        else
          "Possibly conflicting definition of #{state}"
        end
        @context[DiagnosticListener].report(MirahDiagnostic.new(
            conflict, state.position, desc))
        note("Previous definition of #{m}", m.position)
        return
      end
    end
    methods.add(state)
  end

  def enterDefault(node, arg)
    error("Statement (#{node.getClass}) not enclosed in a method", node.position)
    false
  end

  def enterMethodDefinition(node, arg)
    @field_collector.collect(node.body, node)
    MethodCleanup.new(@context, node).clean
    @methods.add(node)
    addMethodState(MethodState.new(
        node, @typer.getResolvedType(node):MethodType))
    false
  end

  def enterStaticMethodDefinition(node, arg)
    @field_collector.collect(node.body, node)
    if "initialize".equals(node.name.identifier)
      setCinit(node)
    end
    @methods.add(node)
    MethodCleanup.new(@context, node).clean
    addMethodState(MethodState.new(
        node, @typer.getResolvedType(node):MethodType))
    false
  end

  def isStatic(node:Node)
    @typer.scoper.getScope(node).selfType.resolve.isMeta
  end

  def setCinit(node:MethodDefinition):void
    unless @cinit.nil?
      error("Duplicate static initializer", node.position)
      note("Previously declared here", @cinit.position) if @cinit.position
      return
    end
    @cinit = node
  end

  def enterConstructorDefinition(node, arg)
    @constructors.add(node)
    @field_collector.collect(node.body, node)
    MethodCleanup.new(@context, node).clean
    @methods.add(node)
    addMethodState(MethodState.new(
        node, @typer.getResolvedType(node):MethodType))
    false
  end
  
  def enterClassDefinition(node, arg)
    ClassCleanup.new(@context, node).clean
    false
  end

  def enterInterfaceDeclaration(node, arg)
    enterClassDefinition(node, arg)
    false
  end

  def enterImport(node, arg)
    # ignore
    false
  end

  def enterNoop(node, arg)
    # ignore
    false
  end

  def enterNodeList(node, arg)
    # Scan the children
    true
  end

  def enterClassAppendSelf(node, arg)
    # Scan the children
    true
  end

  def enterConstantAssign(node, arg)
    @static_init_nodes.add(node)
    false
  end

  def enterFieldAssign(node, arg)
    @field_collector.collect(node, @klass)
    if node.isStatic || isStatic(node)
      @static_init_nodes.add(node)
    else
      @init_nodes.add(node)
    end
    false
  end

  def enterFieldAnnotationRequest(node, arg)
    field_annotation_requestss[node.name.identifier] ||= []
    field_annotation_requestss[node.name.identifier]:List.add(node)
    false
  end

  def enterFieldDeclaration(node, arg)
    # We've already cleaned this class, don't add more field decls.
    @alreadyCleaned = true
    false
  end

  def enterMacroDefinition(node, arg)
    addMethodState(MethodState.new(node))
    false
  end

  def enterJavaDoc(node, arg)
    # just skip
    false
  end


  def addOptionalMethods(mdef:MethodDefinition):void
    if mdef.arguments.optional_size > 0
      parent = mdef.parent:NodeList
      params = buildDefaultParameters(mdef.arguments)
      new_args = mdef.arguments.clone:Arguments
      num_optional_args = new_args.optional_size
      optional_arg_offset = new_args.required_size
      @@log.fine("Generating #{num_optional_args} optarg methods for #{mdef.name.identifier}")
      (num_optional_args - 1).downto(0) do |i|
        @@log.finer("Generating optarg method #{i}")
        arg = new_args.optional.remove(i)
        params.set(optional_arg_offset + i, arg.value)
        method = buildOptargBridge(mdef, new_args, params)
        # TODO better handle bridge java doc
        orig_java_doc = mdef.java_doc
        parent.add(orig_java_doc) if orig_java_doc

        parent.add(method)
        @typer.infer(method)
      end
    end
  end
  
  def buildDefaultParameters(args:Arguments):List
    params = ArrayList.new
    args.required_size.times do |i|
      arg = args.required(i)
      params.add(LocalAccess.new(arg.position, arg.name))
    end
    args.optional_size.times do |i|
      optarg = args.optional(i)
      params.add(LocalAccess.new(optarg.position, optarg.name))
    end
    if args.rest
      params.add(LocalAccess.new(args.rest.position, arg.name))
    end
    args.required2_size.times do |i|
      arg = args.required2(i)
      params.add(LocalAccess.new(arg.position, arg.name))
    end
    params
  end
  
  def buildOptargBridge(orig:MethodDefinition, args:Arguments, params:List):Node
    mdef = orig.clone:MethodDefinition
    mdef.arguments = args.clone:Arguments
    mdef.body = NodeList.new([FunctionalCall.new(mdef.position, mdef.name, params, nil)])
    mdef.modifiers = ModifierList.new([Modifier.new(mdef.position, 'PUBLIC'), Modifier.new(mdef.position, 'SYNTHETIC'), Modifier.new(mdef.position, 'BRIDGE')])
  end
end
