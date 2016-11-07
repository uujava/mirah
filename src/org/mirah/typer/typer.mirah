# Copyright (c) 2015 The Mirah project authors. All Rights Reserved.
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

package org.mirah.typer

import java.util.*
import org.mirah.util.Logger
import mirah.lang.ast.Float as AstFloat
import mirah.lang.ast.*
import mirah.impl.MirahParser
import org.mirah.macros.JvmBackend
import org.mirah.macros.MacroBuilder
import mirah.objectweb.asm.Opcodes

import static org.mirah.jvm.types.JVMTypeUtils.*
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.mirrors.*

# Type inference engine.
# Makes a single pass over the AST nodes building a graph of the type
# dependencies. Whenever a new type is learned or a type changes any dependent
# types get updated.
#
# An important feature is that types will change over time.
# The first time an assignment to a variable resolves, the typer will pick that
# type for the variable. When a new assignment resolves, two things can happen:
#  - if the assigned type is compatible with the old, just continue.
#  - otherwise, widen the inferred type to include both and update any dependencies.
# This also allows the typer to handle recursive calls. Consider fib for example:
#   def fib(i:int); if i < 2 then 1 else fib(i - 1) + fib(i - 2) end; end
# The type of fib() depends on the if statement, which also depends on the type
# of fib(). The first branch infers first though, marking the if statement
# as type 'int'. This updates fib() to also be type 'int'. This in turn causes
# the if statement to check that both its branches are compatible, and they are
# so the method is resolved.
#
# Some nodes can have multiple meanings. For example, a VCall could mean a
# LocalAccess or a FunctionalCall. The typer will try each possibility,
# and update the AST tree with the one that doesn't infer as an error. There
# is always a priority implied when multiple options succeed. For example,
# a LocalAccess always wins over a FunctionalCall.
#
# This typer is type system independent. It relies on a TypeSystem and a Scoper
# to provide the types for methods, literals, variables, etc.
class Typer < SimpleNodeVisitor

  def self.initialize:void
    @@log = Logger.getLogger(Typer.class.getName)
  end

  def initialize(types: TypeSystem,
                 scopes: Scoper,
                 jvm_backend: JvmBackend,
                 parser: MirahParser=nil)
    @trueobj = java::lang::Boolean.valueOf(true)
    @futures = HashMap.new
    @types = types
    @scopes = scopes
    @macros = MacroBuilder.new(self, jvm_backend, parser)

    # might want one of these for each script
    @closures = BetterClosureBuilder.new(self, @macros)
  end

  def finish_closures
    @closures.finish
  end

  def macro_compiler
    @macros
  end

  def macro_compiler=(compiler: MacroBuilder)
    @macros = compiler
  end

  def type_system
    @types
  end

  def scoper
    @scopes
  end

  def getInferredType(node: Node)
    @futures[node]:TypeFuture
  end

  def getResolvedType(node: Node)
    future = getInferredType(node)
    if future
      future.resolve
    else
      nil
    end
  end

  def inferTypeName(node: TypeName)
    @futures[node] ||= getTypeOf(node, node.typeref)
    @futures[node]:TypeFuture
  end

  def learnType(node:Node, type:TypeFuture):void
    existing = @futures[node]
    raise IllegalArgumentException, "had existing type #{existing}" if existing
    @futures[node] = type
  end

  def infer(node:Node, expression:boolean=true)
    @@log.entering("Typer", "infer", "infer(#{node})")

    return nil if node.nil?
    type = @futures[node]
    if type.nil?
      @@log.fine("source:\n    #{sourceContent node}")
      type = node.accept(self, expression ? @trueobj : nil)
      @futures[node] ||= type
    end
    type:TypeFuture
  end

  def infer(node: Object, expression:boolean=true)
    infer(node:Node, expression)
  end

  def inferAll(nodes:NodeList)
    types = ArrayList.new
    nodes.each {|n| types.add infer(n) } if nodes
    types
  end

  def inferAll(nodes:AnnotationList)
    types = ArrayList.new
    nodes.each {|n| types.add infer(n) } if nodes
    types
  end

  def inferAll(arguments: Arguments)
    types = ArrayList.new
    arguments.required.each {|a| types.add infer(a) } if arguments.required
    arguments.optional.each {|a| types.add infer(a) } if arguments.optional
    types.add infer(arguments.rest) if arguments.rest
    arguments.required2.each {|a| types.add infer(a) } if arguments.required2
    types.add infer(arguments.block) if arguments.block
    types
  end

  def inferAll(scope: Scope, typeNames: TypeNameList)
    types = ArrayList.new
    typeNames.each {|n| types.add(inferTypeName(n:TypeName))}
    types
  end

  def defaultNode(node, expression)
    #return node:TypeFutureTypeRef.type_future if node.kind_of? TypeFutureTypeRef
    ErrorType.new([["Inference error: unsupported node #{node}", node.position]])
  end

  def logger
    @@log
  end

  def visitVCall(call, expression)
    @@log.fine "visitVCall #{call}"

    # This might be a local, method call, or primitive access,
    # so try them all.

    #fcall = FunctionalCall.new(call.position,
    #                           call.name.clone:Identifier,
    #                           nil, nil)
    #fcall.setParent(call.parent)

    #@futures[fcall] = callMethodType call, Collections.emptyList
    #@futures[fcall.target] = infer(call.target)

    proxy = ProxyNode.new(self, call)
    proxy.setChildren([LocalAccess.new(call.position, call.name),
                       FunctionalCall.new(call.position, call.name.clone:Identifier, nil, nil),
                       Constant.new(call.position, call.name)], 0)

    @futures[proxy] = proxy.inferChildren(expression != nil)
  end

  def visitFunctionalCall(call, expression)

    # if we have (a -1) => Call(a, [Call(-@, 1)]) we also should try Call(-, [a, 1])
    # check AST before inferring rewrite call parameters
    rwr_unary = get_rewrite_unary(call)

    parameters = inferParameterTypes call
    @futures[call] = callMethodType(call, parameters)

    proxy = ProxyNode.new(self, call)
    children = ArrayList.new(2)
    children.add(call)
    if call.parameters.size == 1
      # This might actually be a cast instead of a method call, so try
      # both. If the cast works, we'll go with that. If not, we'll leave
      # the method call.
      children.add(Cast.new(call.position, call.typeref:TypeName,
                            call.parameters.get(0).clone:Node))
    end

    scope = scopeOf(call)
    # support calls to outer methods for closures
    if scope.kind_of? ClosureScope
      outer = FieldAccess.new(call.position, SimpleString.new(call.position, '$outer'))
      outer_scope = scope.find_parent { |s| !s.kind_of? ClosureScope }
      @futures[outer] = outer_scope.selfType
      params = []
      call.parameters.each { |p| params.add p }
      children.add Call.new(call.position, outer, call.name, params, call.block)
    end
    children.add(rwr_unary) if rwr_unary
    proxy.setChildren(children, 0)

    # have to infer cloned params for rewritten unary call
    infer_rewrite_unary rwr_unary
    @futures[proxy] = proxy.inferChildren(expression != nil)
  end

  def visitElemAssign(assignment, expression)
    value_type = infer(assignment.value)
    value = assignment.value
    assignment.removeChild(value)
    if value_type.kind_of?(NarrowingTypeFuture)
      narrowingCall(scopeOf(assignment),
                    infer(assignment.target),
                    '[]=',
                    inferAll(assignment.args),
                    value_type:NarrowingTypeFuture,
                    assignment.position)
    end
    call = Call.new(assignment.position, assignment.target, SimpleString.new('[]='), nil, nil)
    call.parameters = assignment.args
    if expression
      temp = scopeOf(assignment).temp('val')
      call.parameters.add(LocalAccess.new(SimpleString.new(temp)))
      newNode = Node(NodeList.new([
        LocalAssignment.new(SimpleString.new(temp), value),
        call,
        LocalAccess.new(SimpleString.new(temp))
      ]))
    else
      call.parameters.add(value)
      newNode = call:Node
    end
    newNode = replaceSelf(assignment, newNode)
    infer(newNode)
  end

  def visitCall(call, expression)
    proxy = ProxyNode.new(self, call)
    children = ArrayList.new(3)
    children.add(call)
    # if we have (a -1) => Call(a, [Call(-@, 1)]) we also should try Call(-, [a, 1])
    # check AST before inferring rewrite call parameters
    rwr_unary = get_rewrite_unary(call)

    target = infer(call.target)
    parameters = inferParameterTypes call

    @futures[call] = CallFuture.new(@types,
                                    scopeOf(call),
                                    target,
                                    true,
                                    parameters,
                                    call)
    if  call.parameters.size == 1
      # This might actually be a cast or array instead of a method call, so try
      # both. If the cast works, we'll go with that. If not, we'll leave
      # the method call.
      is_array = '[]'.equals(call.name.identifier)
      if is_array
        typeref = call.target:TypeName.typeref if call.target.kind_of?(TypeName)
      else
        typeref = call.typeref(true)
      end
      if typeref
        children.add(if is_array
          EmptyArray.new(call.position, typeref, call.parameters(0))
        else
          Cast.new(call.position, typeref:TypeName,
                   call.parameters(0).clone:Node)
        end)
      end
    end
    children.add(rwr_unary) if rwr_unary
    proxy.setChildren(children, 0)
    # have to infer cloned params for rewritten unary call
    infer_rewrite_unary rwr_unary
    @futures[proxy] = proxy.inferChildren(expression != nil)
  end

  def visitAttrAssign(call, expression)
    target = infer(call.target)
    value = infer(call.value)
    name = call.name.identifier
    setter = "#{name}_set"
    scope = scopeOf(call)
    if (value.kind_of?(NarrowingTypeFuture))
      narrowingCall(scope, target, setter, Collections.emptyList, value:NarrowingTypeFuture, call.position)
    end
    CallFuture.new(@types, scope, target, true, setter, [value], nil, call.position)
  end

  def narrowingCall(scope:Scope,
                    target:TypeFuture,
                    name:String,
                    param_types:List,
                    value:NarrowingTypeFuture,
                    position:Position):void
    # Try looking up both the wide type and the narrow type.
    wide_params = LinkedList.new(param_types)
    wide_params.add(value.wide_future)
    wide_call = CallFuture.new(@types, scope, target, true, name, wide_params, nil, position)

    narrow_params = LinkedList.new(param_types)
    narrow_params.add(value.narrow_future)
    narrow_call = CallFuture.new(@types, scope, target, true, name, narrow_params, nil, position)

    # If there's a match for the wide type (or both are errors) we always use
    # the wider one.
    wide_is_error = true
    narrow_is_error = true
    wide_call.onUpdate do |x, resolved|
      wide_is_error = resolved.isError
      if wide_is_error && !narrow_is_error
        value.narrow
      else
        value.widen
      end
    end
    narrow_call.onUpdate do |x, resolved|
      narrow_is_error = resolved.isError
      if wide_is_error && !narrow_is_error
        value.narrow
      else
        value.widen
      end
    end
  end

  # Should be verified by JLS 5.5 Casting Contexts
  def isCastable(resolved_cast_type: ResolvedType, resolved_value_type: ResolvedType): boolean
    are_jvm_types = resolved_cast_type.kind_of?(JVMType) && resolved_value_type.kind_of?(JVMType)
    if are_jvm_types
      if isPrimitive(resolved_cast_type:JVMType) &&
         isPrimitive(resolved_value_type:JVMType)
         return true
      elsif isPrimitive(resolved_value_type:JVMType) &&
           supportBoxing(resolved_cast_type:JVMType)
         # it's a bit off JLS  - we always cast from primitive to boxed number. Check logic in MethodCompiler#visitCast
         return true
       elsif isPrimitive(resolved_cast_type:JVMType) &&
                 supportBoxing(resolved_value_type:JVMType)
         # it's a bit off JLS  - we always cast from Boxed to primitive. Check logic in MethodCompiler#visitCast
         return true
      end
    end
    if resolved_value_type.assignableFrom(resolved_cast_type)
      return true
    elsif resolved_cast_type.assignableFrom(resolved_value_type)
      return true
    else
      # avoid error when casting to from interfaces (JLS 5.5.1) for non final classes
      # Here we do not have common subtypes as this check already done above.
      # Note! Currently do not support generics checks
      if  are_jvm_types
        are_final = resolved_value_type:JVMType.flags & Opcodes.ACC_FINAL !=0 || resolved_cast_type:JVMType.flags  & Opcodes.ACC_FINAL !=0
        are_interfaces = resolved_value_type:JVMType.isInterface || resolved_cast_type:JVMType.isInterface
        if are_final
          return false
        elsif are_interfaces
          return true
        end
      end
      return false
    end
  end

  def isNotReallyResolvedDoOnIncompatibility(resolved: ResolvedType, runnable: Runnable): boolean
    import org.mirah.jvm.mirrors.AsyncMirror
    if resolved.kind_of?(AsyncMirror) && resolved:AsyncMirror.superclass.nil?
      resolved:AsyncMirror.onIncompatibleChange runnable
      true
    elsif resolved.kind_of?(MirrorProxy)                            &&
          resolved:MirrorProxy.target.kind_of?(AsyncMirror)        &&
          resolved:MirrorProxy.target:AsyncMirror.superclass.nil?
      resolved:MirrorProxy.target:AsyncMirror.onIncompatibleChange runnable
      true
    else
      false
    end
  end

  def checkCastabilityAndUpdate(future: DelegateFuture,
                                resolved_cast_type: ResolvedType,
                                resolved_value_type: ResolvedType,
                                cast_position: Position,
                                cast_future: TypeFuture)
    if isCastable(resolved_cast_type, resolved_value_type)
      # fine, but may need to undo erroring
      future.type = cast_future
    else
      future.type = ErrorType.new([["Cannot cast #{resolved_value_type} to #{resolved_cast_type}.", cast_position]])
    end
  end

  def updateCastFuture(future: DelegateFuture,
                       resolved_cast_type: ResolvedType,
                       resolved_value_type: ResolvedType,
                       cast_position: Position,
                       cast_type: TypeFuture)
    typer = self
    if typer.isNotReallyResolvedDoOnIncompatibility(resolved_cast_type) do
        typer.checkCastabilityAndUpdate(future,
                                        resolved_cast_type,
                                        resolved_value_type,
                                        cast_position,
                                        cast_type)
      end
    elsif typer.isNotReallyResolvedDoOnIncompatibility(resolved_value_type) do
        typer.checkCastabilityAndUpdate(future,
                                        resolved_cast_type,
                                        resolved_value_type,
                                        cast_position,
                                        cast_type)
      end
    else
      typer.checkCastabilityAndUpdate(future,
                                      resolved_cast_type,
                                      resolved_value_type,
                                      cast_position,
                                      cast_type)
    end
  end

  def visitCast(cast, expression)
    value_type = infer(cast.value)
    cast_type = getTypeOf(cast, cast.type.typeref)

    future = DelegateFuture.new
    future.type = cast_type
    log = @@log
    typer = self

    value_type.onUpdate do |x, resolved_value_type|
      if cast_type.isResolved
        resolved_cast_type = cast_type.resolve
        typer.updateCastFuture(future,
                               resolved_cast_type,
                               resolved_value_type,
                               cast.position,
                               cast_type)
      end
    end
    cast_type.onUpdate do |x, resolved_cast_type|
      if value_type.isResolved
        resolved_value_type = value_type.resolve
        typer.updateCastFuture(future,
                               resolved_cast_type,
                               resolved_value_type,
                               cast.position,
                               cast_type)
      end
    end
    future
  end

  def visitColon2(colon2, expression)
    @futures[colon2] = @types.getMetaType(getTypeOf(colon2, colon2.typeref))

    # A colon2 is either a type ref or a constant ref.
    # If it's a constant, we need to use Call lookup to find it.
    # Atleast that's my understanding based on reading Constant.
    #
    # This works for external constants, but not internal ones currently.
    variants = [colon2]
    if expression
      variants.add Call.new(colon2.position,
                                         colon2.target,
                                         colon2.name.clone:Identifier,
                                         nil, nil)
    end
    proxy = ProxyNode.new self, colon2
    proxy.setChildren(variants, 0)

    @futures[proxy] = proxy.inferChildren(expression != nil)
  end

  def visitSuper(node, expression)
    method:MethodDefinition = node.findAncestor(MethodDefinition.class)
    scope = scopeOf(node)
    parameters = inferParameterTypes node
    if method.kind_of? ConstructorDefinition
      target = @types.getSuperClass(scope.selfType)
      CallFuture.new(@types, scope, target, true, method.name.identifier, parameters, nil, node.position)
    else
      # handle super for interface default methods:
      # use selfType for method lookup
      # defer supertype or superinterface check to method compiler
      CallFuture.new(@types, scope, scope.selfType, true, method.name.identifier, parameters, nil, node.position)
    end
  end

  def visitZSuper(node, expression)
    method:MethodDefinition = node.findAncestor(MethodDefinition.class)
    locals = LinkedList.new
    [ method.arguments.required,
        method.arguments.optional,
        method.arguments.required2].each do |args|
      args:Iterable.each do |arg|
        farg = arg:FormalArgument
        local = LocalAccess.new(farg.position, farg.name)
        @scopes.copyScopeFrom(farg, local)
        infer(local, true)
        locals.add(local)
      end
    end
    replacement = Super.new(node.position, locals, nil)
    infer(replaceSelf(node, replacement), expression != nil)
  end

  def visitClassDefinition(classdef, expression)
    classdef.annotations.each {|a| infer(a)}
    scope = scopeOf(classdef)
    interfaces = inferAll(scope, classdef.interfaces)
    superclass = if classdef.superclass
      @types.get(scope, classdef.superclass.typeref)
    elsif classdef.kind_of? EnumDefinition
       @types.get(scope, TypeRefImpl.new('java.lang.Enum', false, false, classdef.position))
    end
    name = if classdef.name
      classdef.name.identifier
    end
    type = @types.createType(scope, classdef, name, superclass, interfaces)
    addScopeWithSelfType(classdef, type)
    infer(classdef.body, false) if classdef.body
    @types.publishType(type)
    type
  end

  def visitClosureDefinition(classdef, expression)
    visitClassDefinition(classdef, expression)
  end

  def visitInterfaceDeclaration(idef, expression)
    visitClassDefinition(idef, expression)
  end

  def visitEnumDefinition(enum_def, expression)
    visitClassDefinition(EnumRewriter.new(self).rewrite(enum_def), expression)
  end

  def visitFieldAnnotationRequest(decl, expression)
    @types.getNullType()
  end

  def visitFieldDeclaration(decl, expression)
    inferAnnotations decl
    getFieldTypeOrDeclare(decl).declare(
                          getTypeOf(decl, decl.type.typeref),
                          decl.position)
  end

  def visitFieldAssign(field, expression)
    inferAnnotations field
    _value = field.value
    if field.type_hint
       _value = replaceSelf(_value, Cast.new(_value.position, field.type_hint, _value))
    end
    value_future = infer(_value, true)
    getFieldTypeOrDeclare(field).assign(value_future, field.position)
  end

  def visitConstantAssign(field, expression)
    newField = FieldAssign.new field.name,
                 field.value,
                 nil,
                 [Modifier.new(field.position, "PUBLIC"), Modifier.new(field.position, "FINAL")],
                 field.type_hint
    newField.isStatic = true
    newField.position = field.position

    replaceSelf field, newField

    infer(newField, expression != nil)
  end

  def visitFieldAccess(field, expression)
    targetType = fieldTargetType field, field.isStatic
    if targetType.nil?
      ErrorType.new([["Cannot find declaring class for field.", field.position]]):TypeFuture
    else
      getFieldType field, targetType
    end
  end

  def visitConstant(constant, expression)

    @futures[constant] = @types.getMetaType(getTypeOf(constant, constant.typeref))

    fieldAccess = FieldAccess.new(constant.position, constant.name.clone:Identifier)
    fieldAccess.isStatic = true
    fieldAccess.position = constant.position
    variants = [constant, fieldAccess]

    # This could be Constant in static import, currently implemented by method lookup
    # Not sure should we restrict method lookup to select constants only
    # and not to infer to methods as well
    # If adding fcall without expression check - getting method duplicates in
    # macros_test.rb#test_macro_changes_body_of_class_last_element
    if expression
      variants.add FunctionalCall.new(constant.position,
                                                  constant.name.clone:Identifier,
                                                  nil, nil)
    end
    proxy = ProxyNode.new self, constant
    proxy.setChildren(variants, 0)

    @futures[proxy] = proxy.inferChildren(expression != nil)
  end

  def visitIf(stmt, expression)
    infer(stmt.condition, true)
    a = infer(stmt.body, expression != nil) if stmt.body
    # Can there just be an else? Maybe we could simplify below.
    b = infer(stmt.elseBody, expression != nil) if stmt.elseBody
    if expression && a && b
      type = AssignableTypeFuture.new(stmt.position)
      type.assign(a, stmt.body.position)
      type.assign(b, stmt.elseBody.position)
      type:TypeFuture
    else
      a || b
    end
  end

  def visitLoop(node, expression)
    enhanceLoop(node)
    infer(node.init, false)
    infer(node.condition, true)
    infer(node.pre, false)
    infer(node.body, false)
    infer(node.post, false)
    @types.getNullType()
  end

  def visitReturn(node, expression)
    type = if node.value
      infer(node.value)
    else
      @types.getVoidType()
    end
    enclosing_node = node.findAncestor {|n| n.kind_of?(MethodDefinition) || n.kind_of?(Script)}
    if enclosing_node.kind_of? MethodDefinition
      return nil if isMethodInBlock(enclosing_node:MethodDefinition) # return types are not supported currently for methods which act as templates
      methodType = infer enclosing_node
      returnType = methodType:MethodFuture.returnType
      assignment = returnType.assign(type, node.position)
      future = DelegateFuture.new
      future.type = returnType
      assignment.onUpdate do |x, resolved|
        if resolved.isError
          future.type = assignment
        else
          future.type = returnType
        end
      end
      future:TypeFuture
    elsif enclosing_node.kind_of? Script
      @types.getVoidType:TypeFuture
    end
  end

  def visitBreak(node, expression)
    @types.getNullType()
  end

  def visitNext(node, expression)
    @types.getNullType()
  end

  def visitRedo(node, expression)
    @types.getNullType()
  end

  def visitRaise(node, expression)
    # Ok, this is complicated. There's three acceptable syntaxes
    #  - raise exception_object
    #  - raise ExceptionClass, *constructor_args
    #  - raise *args_for_default_exception_class_constructor
    # We need to figure out which one is being used, and replace the
    # args with a single exception node.

    # TODO(ribrdb): Clean this up using ProxyNode.

    # Start by saving the old args and creating a new, empty arg list
    old_args = node.args
    node.args = NodeList.new(node.args.position)
    possibilities = ArrayList.new
    exceptions = ArrayList.new
    if old_args.size == 1
      exceptions.addAll buildNodeAndTypeForRaiseTypeOne(old_args, node)
      possibilities.add "1"
    end

    if old_args.size > 0
      exceptions.addAll buildNodeAndTypeForRaiseTypeTwo(old_args, node)
      possibilities.add "2"
    end
    exceptions.addAll buildNodeAndTypeForRaiseTypeThree(old_args, node)
      possibilities.add "3"

    log = logger()
    log.finest "possibilities #{possibilities}"
    exceptions.each do |e|
      log.finest "type possible #{e} for raise"
    end
    # Now we'll try all of these, ignoring any that cause an inference error.
    # Then we'll take the first that succeeds, in the order listed above.
    exceptionPicker = PickFirst.new(exceptions) do |type, pickedNode|
      log.finest "picking #{type} for raise"
      if node.args.size == 0
        node.args.add(pickedNode:Node)
      else
        node.args.set(0, pickedNode:Node)
      end
    end

    # We need to ensure that the chosen node is an exception.
    # So create a dummy type declared as an exception, and assign
    # the picker to it.
    exceptionType = AssignableTypeFuture.new(node.position)
    exceptionType.declare(@types.getBaseExceptionType(), node.position)
    assignment = exceptionType.assign(exceptionPicker, node.position)

    # Now we're ready to return our type. It should be UnreachableType.
    # But if none of the nodes is an exception, we need to return
    # an error.
    myType = BaseTypeFuture.new(node.position)
    unreachable = UnreachableType.new
    assignment.onUpdate do |x, resolved|
      if resolved.isError
        myType.resolved(resolved)
      else
        myType.resolved(unreachable)
      end
    end
    myType
  end

  def visitRescueClause(clause, expression)
    if clause.types_size == 0
      clause.types.add(TypeRefImpl.new(defaultExceptionTypeName,
                                       false, false, clause.position))
    end
    scope = addNestedScope clause
    name = clause.name
    if name
      scope.shadow(name.identifier)
      exceptionType = @types.getLocalType(scope, name.identifier, name.position)
      clause.types.each do |_t|
        t = _t:TypeName
        exceptionType.assign(inferTypeName(t), t.position)
      end
    else
      inferAll(scope.parent, clause.types)
    end
    # What if body is nil?
    infer(clause.body, expression != nil)
  end

  def visitRescue(node, expression)
    # AST contains an empty else clause even if there isn't one
    # in the source. Once, the parser's compiling, we should fix it.
    hasElse = !(node.elseClause.nil? || node.elseClause.size == 0)
    bodyType = infer(node.body, expression && !hasElse) if node.body
    elseType = infer(node.elseClause, expression != nil) if hasElse
    if expression
      myType = AssignableTypeFuture.new(node.position)
      if hasElse
        myType.assign(elseType, node.elseClause.position)
      else
        myType.assign(bodyType, node.body.position)
      end
    end
    node.clauses.each do |clause|
      clauseType = infer(clause, expression != nil)
      myType.assign(clauseType, clause:Node.position) if expression
    end

    myType:TypeFuture || @types.getNullType
  end

  def visitEnsure(node, expression)
    infer(node.ensureClause, false)
    infer(node.body, expression != nil)
  end

  def visitArray(array, expression)
    mergeUnquotes(array.values)
    component = AssignableTypeFuture.new(array.position)
    array.values.each do |v|
      node = v:Node
      component.assign(infer(node, true), node.position)
    end
    @types.getArrayLiteralType(component, array.position)
  end

  def visitFixnum(fixnum, expression)
    @types.getFixnumType(fixnum.value)
  end

  def visitFloat(number, expression)
    @types.getFloatType(number.value)
  end

  def visitNot(node, expression)
    type = BaseTypeFuture.new(node.position)
    null_type = @types.getNullType.resolve
    boolean_type = @types.getBooleanType.resolve
    infer(node.value).onUpdate do |x, resolved|
      if (null_type.assignableFrom(resolved) ||
          boolean_type.assignableFrom(resolved))
        type.resolved(boolean_type)
      else
        type.resolved(ErrorType.new([["#{resolved} not compatible with boolean", node.position]]))
      end
    end
    type
  end

  def visitHash(hash, expression)
    keyType = AssignableTypeFuture.new(hash.position)
    valueType = AssignableTypeFuture.new(hash.position)
    hash.each do |e|
      entry = e:HashEntry
      keyType.assign(infer(entry.key, true), entry.key.position)
      valueType.assign(infer(entry.value, true), entry.value.position)
      infer(entry, false)
    end
    @types.getHashLiteralType(keyType, valueType, hash.position)
  end

  def visitHashEntry(entry, expression)
    @types.getVoidType
  end

  def visitRegex(regex, expression)
    regex.strings.each {|r| infer(r)}
    @types.getRegexType()
  end

  def visitSimpleString(string, expression)
    @types.getStringType()
  end

  def visitStringConcat(string, expression)
    string.strings.each {|s| infer(s)}
    @types.getStringType()
  end

  def visitStringEval(string, expression)
    infer(string.value)
    @types.getStringType()
  end

  def visitBoolean(bool, expression)
    @types.getBooleanType()
  end

  def visitNull(node, expression)
    @types.getNullType()
  end

  def visitCharLiteral(node, expression)
    @types.getCharType(node.value)
  end

  def visitSelf(node, expression)
    scopeOf(node).selfType
  end

  def visitTypeRefImpl(typeref, expression)
    getTypeOf(typeref, typeref)
  end

  def visitLocalDeclaration(decl, expression)
    type = getTypeOf(decl, decl.type.typeref)
    getLocalType(decl).declare(type, decl.position)
  end

  def visitLocalAssignment(local, expression)
    _value = local.value
    if local.type_hint
      _value = replaceSelf(_value, Cast.new(_value.position, local.type_hint, _value))
    end
    value = infer(_value, true)
    getLocalType(local).assign(value, local.position)
  end

  def visitLocalAccess(local, expression)
    getLocalType(local)
  end

  def visitNodeList(body, expression)
    if body.size > 0
      i = 0
      while i < body.size # note that we re-evaluate body.size each time, as body.size may change _during_ infer(), as macros may change the AST
        res = infer(body.get(i),(i<body.size-1) ? false : expression != nil)
        i += 1
      end
      res
    else
      @types.getImplicitNilType()
    end
  end

  def visitClassAppendSelf(node, expression)
    addScopeWithSelfType node, @types.getMetaType(scopeOf(node).selfType)
    infer(node.body, false)
    @types.getNullType()
  end

  def visitNoop(noop, expression)
    @types.getVoidType()
  end

  def visitScript(script, expression)
    scope = addScopeUnder(script)
    @types.addDefaultImports(scope)
    scope.selfType = @types.getMainType(scope, script)
    infer(script.body, false)
    @types.getVoidType
  end

  def visitAnnotation(anno, expression)
    anno.values_size.times do |i|
      infer(anno.values(i).value)
    end
    getTypeOf(anno, anno.type.typeref)
  end

  def visitImport(node, expression)
    scope = scopeOf(node)
    fullName = node.fullName.identifier
    simpleName = node.simpleName.identifier
    @@log.fine "import full: #{fullName} simple: #{simpleName}"
    imported_type = if ".*".equals(simpleName)
                      # TODO support static importing a single method
                      type = @types.getMetaType(@types.get(scope, node.fullName:Node:TypeName.typeref))
                      scope.staticImport(type)
                      type
                    else
                      scope.import(fullName, simpleName)
                      unless '*'.equals(simpleName)
                        @@log.fine "wut wut. "
                        @types.get(scope, node.fullName:Node:TypeName.typeref)
                      end
                    end
    void_type = @types.getVoidType
    if imported_type
      DerivedFuture.new(imported_type) do |resolved|
        if resolved.isError
          resolved
        else
          void_type.resolve
        end
      end
    else
      void_type
    end
  end

  def visitPackage(node, expression)
    if node.body
      scope = addScopeUnder(node)
      scope.package = node.name.identifier
      infer(node.body, false)
    else
      # TODO this makes things complicated. Probably package should be a property of
      # Script, and Package nodes should require a body.
      scope = scopeOf(node)
      scope.package = node.name.identifier
      scope.selfType = @types.getMainType(scope, node.findAncestor(Script.class):Script)
    end
    @types.getVoidType()
  end

  def visitEmptyArray(node, expression)
    infer(node.size)
    @types.getArrayType(getTypeOf(node, node.type.typeref))
  end

  def visitUnquote(node, expression)
    # Convert the unquote into a NodeList and replace it with the NodeList.
    # TODO(ribrdb) do these need to be cloned?
    nodes = node.nodes
    replacement = if nodes.size == 1
      nodes.get(0):Node
    else
      NodeList.new(node.position, nodes)
    end
    replacement = replaceSelf(node, replacement)
    infer(replacement, expression != nil)
  end

  def visitUnquoteAssign(node, expression)
    replacement = nil:Node
    object = node.unquote.object
    if object.kind_of?(FieldAccess)
      fa = node.name:FieldAccess
      replacement = FieldAssign.new(fa.position, fa.name, node.value, nil, nil, nil)
    else
      replacement = LocalAssignment.new(node.position, node.name, node.value)
    end
    replacement = replaceSelf(node, replacement)
    infer(replacement, expression != nil)
  end

  def visitArguments(args, expression)
    mergeUnquotedArgs(args)

    # Then do normal type inference.
    inferAll(args)
    @types.getVoidType()
  end

  def mergeUnquotedArgs(args:Arguments): void
    it = args.required.listIterator
    mergeArgs(args,
              it,
              it,
              args.optional.listIterator(args.optional_size),
              args.required2.listIterator(args.required2_size))
    it = args.optional.listIterator
    mergeArgs(args,
              it,
              args.required.listIterator(args.required_size),
              it,
              args.required2.listIterator(args.required2_size))
    it = args.required.listIterator
    mergeArgs(args,
              it,
              args.required.listIterator(args.required_size),
              args.optional.listIterator(args.optional_size),
              it)
  end

  def mergeArgs(args:Arguments, it:ListIterator, req:ListIterator, opt:ListIterator, req2:ListIterator):void
    #it.each do |arg|
    while it.hasNext
      arg = it.next:FormalArgument
      name = arg.name
      next unless name.kind_of?(Unquote)
      next if arg.type # If the arg has a type then the unquote must only be an identifier.

      unquote = name:Unquote
      new_args = unquote.arguments
      next unless new_args

      it.remove
      import static org.mirah.util.Comparisons.*
      if areSame(it, req2) && new_args.optional.size == 0 && new_args.rest.nil? && new_args.required2.size == 0
        mergeIterators(new_args.required.listIterator, req2)
      else
        mergeIterators(new_args.required.listIterator, req)
        mergeIterators(new_args.optional.listIterator, opt)
        mergeIterators(new_args.required2.listIterator, req2)
      end
      if new_args.rest
        raise IllegalArgumentException, "Only one rest argument allowed." if args.rest
        rest = new_args.rest
        new_args.rest = nil
        args.rest = rest
      end
      if new_args.block
        raise IllegalArgumentException, "Only one block argument allowed" if args.block
        block = new_args.block
        new_args.block = nil
        args.block = block
      end
    end
  end

  def mergeIterators(source:ListIterator, dest:ListIterator):void
    #source.each do |a|
    while source.hasNext
      a = source.next
      source.remove
      dest.add(a)
    end
  end

  def mergeUnquotes(list:NodeList):void
    it = list.listIterator
    #it.each do |item|
    while it.hasNext
      item = it.next
      if item.kind_of?(Unquote)
        it.remove
        item:Unquote.nodes.each do |node|
          it.add(node)
        end
      end
    end
  end

  def visitRequiredArgument(arg, expression)
    inferAll(arg.annotations)
    getArgumentType arg
  end

  def visitOptionalArgument(arg, expression)
    inferAll(arg.annotations)
    type = getArgumentType arg
    type.assign(infer(arg.value), arg.value.position)
    type
  end

  def visitRestArgument(arg, expression)
    inferAll(arg.annotations)
    if arg.type
      getLocalType(arg).declare(
        @types.getArrayType(getTypeOf(arg, arg.type.typeref)),
        arg.type.position)
    else
      getLocalType(arg)
    end
  end

  def visitJavaDoc(jdoc, expression)
    # just skip
  end

  def addScopeForMethod(mdef: MethodDefinition)
    scope = addScopeWithSelfType(mdef, selfTypeOf(mdef))
    addScopeUnder(mdef)
  end

  def selfTypeOf(mdef: Block): TypeFuture
    selfType = scopeOf(mdef).selfType
    if mdef.kind_of?(StaticMethodDefinition)
      selfType = @types.getMetaType(selfType)
    end
    selfType
  end


  # cp of method def
  def inferClosureBlock(block:Block, method_type: MethodType)
    @@log.entering("Typer", "inferClosureBlock", "inferClosureBlock(#{block})")
    # TODO optional arguments

    #inferAll(block.annotations) # blocks have no annotations
    # block args can be nil...
    parameters = if block.arguments
        infer(block.arguments)
        inferAll(block.arguments)
      else
        []
      end

    if parameters.size != method_type.parameterTypes.size
      position = block.arguments.position if block.arguments
      position ||= block.position
      return @futures[block] = ErrorType.new([
        ["Wrong number of methods for block implementing #{method_type}", position]])

    end
    # parameters.zip(method_type.parameterTypes).each do |...
    i = 0
    parameters.each do |param_type: AssignableTypeFuture|
      if !param_type.hasDeclaration
        future = @types.get(
          scopeOf(block),
          TypeRefImpl.new(
            method_type.parameterTypes.get(i):ResolvedType.name))
        param_type.declare(
                future,
                block.arguments.position)
      end
      i += 1
    end

    selfType = selfTypeOf(block)

    ret_future = AssignableTypeFuture.new(block.position)
    rtype = BaseTypeFuture.new(block.position)
    rtype.resolved((method_type.returnType))
    ret_future.declare(rtype, block.position)


    type = MethodFuture.new(
      method_type.name,
      method_type.parameterTypes,
      ret_future,
      method_type.isVararg,
      block.position)

    @futures[block] = type
    # TODO default arg versions, what do default args even mean for blocks?
    # maybe null -> default?
    # declareOptionalMethods(selfType,
    #                        block,
    #                        parameters,
    #                        type.returnType)

    # TODO deal with overridden methods?
    # TODO throws
    # mdef.exceptions.each {|e| type.throws(@types.get(e:TypeName.typeref))}
    if isVoid type
      infer(block.body, false)
      type.returnType.assign(@types.getVoidType, block.position)
    else
      type.returnType.assign(infer(block.body), block.body.position)
    end
    type
  end


  def visitMethodDefinition(mdef, expression)
    @@log.entering("Typer", "visitMethodDefinition", mdef)
    # TODO optional arguments
    if !isMethodInBlock(mdef)
      scope = addScopeForMethod(mdef)

      # TODO this could be cleaner. This ensures that methods can be closed over
      #BetterScope(scope).methodUsed(mdef.name.identifier) unless mdef.kind_of? StaticMethodDefinition

      @@log.finest "Normal method #{mdef}."
      inferAll(mdef.annotations)
      infer(mdef.arguments)
      parameters = inferAll(mdef.arguments)

      if mdef.type
        returnType = getTypeOf(mdef, mdef.type.typeref)
      end

      flags = calculateFlags(Opcodes.ACC_PUBLIC, mdef)


      selfType = selfTypeOf(mdef)
      resolvedSelf =  selfType.peekInferredType:ResolvedType

      if resolvedSelf.isInterface and !resolvedSelf.isMeta
        # TODO: better handle java8 virtual methods (@see interface_compiler#method_is_not_abstract)
        # note compilers does not use flags from typer?!
        if mdef.body.size == 0
          flags |= Opcodes.ACC_ABSTRACT
        end
      end

      type = @types.getMethodDefType(selfType,
                                   mdef.name.identifier,
                                   flags,
                                   parameters,
                                   returnType,
                                   mdef.name.position)
      @futures[mdef] = type
      declareOptionalMethods(selfType,
                           mdef,
                           flags,
                           parameters,
                           type.returnType)

      # TODO deal with overridden methods?
      # TODO throws
      # mdef.exceptions.each {|e| type.throws(@types.get(e:TypeName.typeref))}
      if isVoid type
        infer(mdef.body, false)
        type.returnType.assign(@types.getVoidType, mdef.position)
      else
        type.returnType.assign(infer(mdef.body), mdef.body.position)
      end
      type
    else  # We are a method defined in a block. We are just a template for a method in a ClosureDefinition
      block = mdef.parent.parent:Block
      @@log.finest "Method #{mdef} is member of #{block}"
      scope_around_block = scopeOf(block)
      scope              = addScopeUnder(mdef)
      scope.selfType     = scope_around_block.selfType
      scope.parent       = scope_around_block # We may want to access variables available in the scope outside of the block.
      infer(mdef.body, false)                 # We want to determine which free variables are referenced in the MethodDefinition.
                                              # But we are actually not interested in the return type of the MethodDefintion, as this special MethodDefinition will be cloned into an AST of an anonymous class.

      # TODO this could be cleaner. This ensures that methods can be closed over
#      unless mdef.kind_of? StaticMethodDefinition
#        @@log.fine "mark #{mdef.name.identifier} as used in #{scope} so that it can be captured by closures"
#        BetterScope(scope).methodUsed(mdef.name.identifier)
#      end
      nil
    end
  end
  
  def declareOptionalMethods(target:TypeFuture, mdef:MethodDefinition, flags:int, argTypes:List, type:TypeFuture):void
    if mdef.arguments.optional_size > 0
      args = ArrayList.new(argTypes)
      first_optional_arg = mdef.arguments.required_size
      last_optional_arg = first_optional_arg + mdef.arguments.optional_size - 1
      last_optional_arg.downto(first_optional_arg) do |i|
        args.remove(i)
        @types.getMethodDefType(target, mdef.name.identifier, flags, args, type, mdef.name.position)
      end
    end
  end

  def visitStaticMethodDefinition(mdef, expression)
    visitMethodDefinition(mdef, expression)
  end

  def visitConstructorDefinition(mdef, expression)
    visitMethodDefinition(mdef, expression)
  end

  def visitImplicitNil(node, expression)
    @types.getImplicitNilType()
  end

  def visitImplicitSelf(node, expression)
    scopeOf(node).selfType
  end

  # TODO is a constructor special?

  def visitBlock(block, expression)
    expandUnquotedBlockArgs(block)
    if block.arguments
      mergeUnquotedArgs(block.arguments)
    end

    closures = @closures
    typer = self
    typer.logger.fine "at block future registration for #{block}"
    BlockFuture.new(block) do |block_future, resolvedType|
      typer.logger.fine "in block future for #{block}: resolvedType=#{resolvedType}\n  #{typer.sourceContent block}"
      closures.add_todo block, resolvedType
    end
  end

  def expandUnquotedBlockArgs(block: Block): void
    expandPipedUnquotedBlockArgs(block)
    expandUnpipedUnquotedBlockArgs(block)
  end

  # expand cases like
  # x = block.arguments
  # quote { y { |`x`| `x.name` +  1 } }
  def expandPipedUnquotedBlockArgs(block: Block): void
    return if block.arguments.nil?
    return if block.arguments.required_size() == 0
    return unless block.arguments.required(0).name.kind_of? Unquote
    unquote_arg = block.arguments.required(0).name:Unquote
    return unless unquote_arg.object.kind_of?(Arguments)

    @@log.finest "Block: expanding unquoted arguments with pipes"
    unquoted_args = unquote_arg.object:Arguments
    block.arguments = unquoted_args
    unquoted_args.setParent block
  end

  def expandUnpipedUnquotedBlockArgs(block: Block): void
    return unless block.arguments.nil?
    return if block.body.nil? || block.body.size == 0
    return unless block.body.get(0).kind_of?(Unquote)
    unquoted_first_element = block.body.get(0):Unquote
    return unless unquoted_first_element.object.kind_of?(Arguments)

    @@log.finest "Block: expanding unquoted arguments with no pipes"
    unquoted_args = unquoted_first_element.object:Arguments
    block.arguments = unquoted_args
    unquoted_args.setParent block
    block.body.removeChild block.body.get(0)
  end

  def visitSyntheticLambdaDefinition(node, expression)
    supertype = infer(node.supertype)
    block     = infer(node.block):BlockFuture
    if node.parameters
      inferAll node.parameters
    end
    SyntheticLambdaFuture.new(supertype,block,node.position)
  end

  # Returns true if any MethodDefinitions were found.
  def contains_methods(block: Block): boolean
    block.body_size.times do |i|
      node = block.body(i)
      return true if node.kind_of?(MethodDefinition)
    end
    return false
  end

  def visitBindingReference(ref, expression)
    binding = scopeOf(ref).binding_type
    future = BaseTypeFuture.new
    future.resolved(binding)
    future
  end

  def visitMacroDefinition(defn, expression)
    @macros.buildExtension(defn)
    #defn.parent.removeChild(defn)
    @types.getVoidType()
  end

  def visitErrorNode(error, expression)
    ErrorType.new([[error.message, error.position]])
  end

  # Look for special blocks in the loop body and move them into the loop node.
  def enhanceLoop(node:Loop):void
    it = node.body.listIterator
    while it.hasNext
      child = it.next
      if child.kind_of?(FunctionalCall)
        call = child:FunctionalCall
        name = call.name.identifier rescue nil
        if name.nil? || call.parameters_size() != 0 || call.block.nil?
          return
        end
        target_list = if name.equals("init")
          node.init
        elsif name.equals("pre")
          node.pre
        elsif name.equals("post")
          node.post
        else
          nil:NodeList
        end
        if target_list
          it.remove
          target_list.add(call.block.body)
        else
          return
          nil
        end
      else
        return
        nil
      end
    end
  end

  def buildNodeAndTypeForRaiseTypeOne(old_args: NodeList, node: Node)
    exception_node = old_args.clone:Node
    exception_node.setParent(node)
    new_type = BaseTypeFuture.new(exception_node.position)
    error = ErrorType.new([["Not an expression", exception_node.position]])
    infer(exception_node).onUpdate do |x, resolvedType|
      # We need to make sure they passed an object, not just a class name
      if resolvedType.isMeta
        new_type.resolved(error)
      else
        new_type.resolved(resolvedType)
      end
    end
    exception_node.setParent(nil)
    # Now we need to make sure the object is an exception, otherwise we
    # need to use a different syntax.
    exceptionType = AssignableTypeFuture.new(exception_node.position)
    exceptionType.declare(@types.getBaseExceptionType(), node.position)
    assignment = exceptionType.assign(new_type, node.position)
    [assignment, exception_node]
  end

  def buildNodeAndTypeForRaiseTypeTwo(old_args: NodeList, node: Node)
    targetNode:Node = old_args.get(0):Node.clone
    params = ArrayList.new
    1.upto(old_args.size - 1) {|i| params.add(old_args.get(i):Node.clone)}
    call = Call.new(node.position, targetNode, SimpleString.new(node.position, 'new'), params, nil)
    wrapper = NodeList.new([call])
    @scopes.copyScopeFrom(node, wrapper)
    [infer(wrapper), wrapper]
  end

  def buildNodeAndTypeForRaiseTypeThree(old_args: NodeList, node: Node)
    targetNode = Constant.new(node.position,
                              SimpleString.new(node.position,
                                defaultExceptionTypeName))
    params = ArrayList.new
    old_args.each {|a| params.add(a:Node.clone)}
    call = Call.new(node.position, targetNode, SimpleString.new(node.position, 'new'), params, nil)
    wrapper = NodeList.new([call])
    @scopes.copyScopeFrom(node, wrapper)
    [infer(wrapper), wrapper]
  end

  def defaultExceptionTypeName
    @types.getDefaultExceptionType().resolve.name
  end

  def selfTypeOf(mdef: MethodDefinition): TypeFuture
    selfType = scopeOf(mdef).selfType
    if mdef.kind_of?(StaticMethodDefinition)
      selfType = @types.getMetaType(selfType)
    end
    selfType
  end

  def isVoid type: MethodFuture
    type.returnType.isResolved && @types.getVoidType().resolve.equals(type.returnType.resolve)
  end

  def getLocalType(local: Named)
    getLocalType(local, local.name.identifier)
  end

  def getLocalType(arg: Node, identifier: String): AssignableTypeFuture
    @types.getLocalType(scopeOf(arg), identifier, arg.position)
  end

  def getArgumentType(arg: FormalArgument)
    type = getLocalType arg
    if arg.type
      type.declare(
        getTypeOf(arg, arg.type.typeref),
        arg.type.position)
    end
    type
  end

  def getTypeOf(node: Node, typeref: TypeRef)
    @types.get(scopeOf(node), typeref)
  end

  def inferCallTarget target: Node, scope: Scope
    targetType = infer(target)
    targetType = @types.getMetaType(targetType) if scope.context.kind_of?(ClassDefinition)
    targetType
  end

  def isMethodInBlock(mdef: MethodDefinition): boolean
    mdef.parent.kind_of?(NodeList) && mdef.parent.parent.kind_of?(Block)
  end

  def addScopeWithSelfType(node: Node, selfType: TypeFuture)
    scope = addScopeUnder(node)
    scope.selfType = selfType
    scope
  end

  def scopeOf(node: Node)
    @scopes.getScope node
  end

  def addScopeUnder(node: Node)
    @scopes.addScope node
  end

  def addNestedScope node: Node
    scope = addScopeUnder(node)
    scope.parent = scopeOf(node)
    scope
  end

  def callMethodType call: CallSite, parameters: List
    scope = scopeOf(call)
    targetType = inferCallTarget call.target, scope
    methodType = CallFuture.new(@types,
                                scope,
                                targetType,
                                false,
                                parameters,
                                call)
  end

  def inferAnnotations annotated: Annotated
    annotated.annotations.each {|a| infer(a)}
  end

  def inferParameterTypes call: CallSite
    mergeUnquotes(call.parameters)
    parameters = inferAll(call.parameters)
    parameters.add(infer(call.block, true)) if call.block
    parameters
  end

  # FIXME: Super should be a CallSite
  def inferParameterTypes call: Super
    mergeUnquotes(call.parameters)
    parameters = inferAll(call.parameters)
    parameters.add(infer(call.block, true)) if call.block
    parameters
  end

    # FIXME: fieldX nodes should have isStatic as an interface method
  def fieldTargetType field: Named, isStatic: boolean
    targetType = scopeOf(field).selfType
    return nil unless targetType
    if isStatic
      @types.getMetaType(targetType)
    else
      targetType
    end
  end

  def getFieldType(field: Named, isStatic: boolean)
    getFieldType(field, fieldTargetType(field, isStatic))
  end

  def getFieldType field: Named, targetType: TypeFuture
    @types.getFieldType(targetType,
                        field.name.identifier,
                        field.position)
  end


  def getFieldTypeOrDeclare(field: FieldAssign)
    getFieldTypeOrDeclare(field, fieldTargetType(field, field.isStatic), field.isStatic, readConstValue(field.value))
  end

  def getFieldTypeOrDeclare(field: FieldDeclaration)
    getFieldTypeOrDeclare(field, fieldTargetType(field, field.isStatic), field.isStatic, nil)
  end

  def getFieldTypeOrDeclare(field: Named, targetType: TypeFuture, isStatic: boolean, constantValue: Object)
    # private by default, static if needed
    flags = calculateFlags(Opcodes.ACC_PRIVATE, field:Node)
    flags |= Opcodes.ACC_STATIC if isStatic
    logger.fine("flags for field #{field.name}  #{targetType}" + flags)
    @types.getFieldTypeOrDeclare(targetType,
                        flags,
                        field.name.identifier,
                        field.position,
                        constantValue)
  end

  def expandMacro node: Node, inline_type: ResolvedType
    logger.fine("Expanding macro #{node}")
    inline_type:InlineCode.expand(node, self)
  end

  def replaceAndInfer(future: DelegateFuture,
    current_node: Node,
    replacement: Node,
    expression: boolean)
    node = replaceSelf(current_node, replacement)
    future.type = infer(node, expression)
    node
  end

  def replaceSelf me: Node, replacement: Node
    me.parent.replaceChild(me, replacement)
  end


  def isMacro resolvedType: ResolvedType
    resolvedType.kind_of?(InlineCode)
  end

  def expandAndReplaceMacro future: DelegateFuture, current_node: Node, fcall: Node, picked_type: ResolvedType, expression: boolean
    if current_node.parent
      replaceAndInfer(
                     future,
                     current_node,
                     expandMacro(fcall, picked_type),
                     expression)
    end
  end

  def sourceContent node: Node
    return "<source non-existent>" unless node
    sourceContent node.position
  end

  def sourceContent pos: Position
    return "<source non-existent>" if pos.nil? || pos.source.nil?
    return "<source start/end negative start:#{pos.startChar} end:#{pos.endChar}>" if  pos.startChar < 0 || pos.endChar < 0
    return "<source start after end start:#{pos.startChar} end:#{pos.endChar}>" if  pos.startChar > pos.endChar

    begin
      pos.source.substring(pos.startChar, pos.endChar)
    rescue => e
      "<error getting source: #{e}  start:#{pos.startChar} end:#{pos.endChar}>"
    end
  end

  def get_rewrite_unary(call:Call):Call
    return nil unless call.parameters
    return nil unless call.parameters.size == 1
    return nil unless call.parameters.get(0).kind_of?(Call)

    unary = call.parameters.get(0):Call
    op = unary.name.identifier
    return nil unless '-@'.equals(op) or '+@'.equals(op)

    operator = op.substring(0,1) # '-' or '+'
    no_arg_call = Call.new(call.position, call.target.clone:Node, call.name.clone:Identifier, [], nil)
    Call.new(unary.position, no_arg_call, SimpleString.new(call.position, operator), [unary.target.clone], nil)

  end

  def get_rewrite_unary(call:FunctionalCall):Call
    return nil unless call.parameters
    return nil unless call.parameters.size == 1
    return nil unless call.parameters.get(0).kind_of?(Call)

    unary = call.parameters.get(0):Call
    op = unary.name.identifier
    return nil unless '-@'.equals(op) or '+@'.equals(op)

    operator = op.substring(0,1) # '-' or '+'
    no_arg_call = VCall.new(call.position, call.name.clone:Identifier)
    Call.new(unary.position, no_arg_call, SimpleString.new(call.position, operator), [unary.target.clone], nil)

  end

  def infer_rewrite_unary(call:Call):void
    if call
      @futures[call.target] = infer(call.target)
      @futures[call.parameters(0)] = infer(call.parameters(0))
    end
  end

  def visitCase(stmt, expression)
    infer(stmt.condition, true)
    a = infer(stmt.elseBody, expression != nil) if stmt.elseBody
    # Can there just be an else? Maybe we could simplify below.
    type = AssignableTypeFuture.new(stmt.position)
    if stmt.elseBody
      elseType = infer(stmt.elseBody, expression != nil)
      type.assign(elseType, stmt.elseBody.position)
    end
    stmt.clauses.each do |clause:WhenClause|
      clauseType = infer(clause, true)
      type.assign(clauseType, clause.body.position)
    end
    type:TypeFuture
  end

  def visitWhenClause(stmt, expression)
    inferAll(stmt.candidates)
    infer(stmt.body, expression != nil)
  end

  def readConstValue(value:Node):Object
    if value.kind_of? SimpleString
      value:SimpleString.value
    elsif value.kind_of? Fixnum
      readFixnumValue(value:Fixnum)
    elsif value.kind_of? CharLiteral
      Character.valueOf(value:CharLiteral.value:char)
    elsif value.kind_of? AstFloat
      readFloatValue(value:AstFloat)
    elsif value.kind_of? Symbol
      value:Symbol.value
    else
      nil
    end
  end

  # this partly duplicates logic from MirrorTypeSystem#getFixnumType
  def readFixnumValue(node:Fixnum)
    value = node.value
    box = value:Long
    if box.intValue != value
      return box
    elsif box.shortValue != value
      return box.intValue:Integer
    elsif box.byteValue != value
      return box.shortValue:Short
    else
      return box.byteValue:Byte
    end
  end

  # this partly duplicates logic from MirrorTypeSystem#getFloatType
  def readFloatValue(node:AstFloat)
    value = node.value
    box = value:Double
    if box.floatValue != value
      return box
    else
      return box.floatValue:Float
    end
  end

end
