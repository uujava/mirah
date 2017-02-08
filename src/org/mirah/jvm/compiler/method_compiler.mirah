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

import java.util.LinkedList
import java.util.Collection
import org.mirah.util.Logger
import mirah.lang.ast.*
import org.mirah.jvm.types.CallType
import org.mirah.jvm.types.JVMType
import org.mirah.typer.ErrorType
import org.mirah.typer.Scope
import org.mirah.util.Context
import mirah.objectweb.asm.*
import mirah.objectweb.asm.Type as AsmType
import mirah.objectweb.asm.commons.GeneratorAdapter
import mirah.objectweb.asm.commons.Method as AsmMethod
import org.mirah.jvm.mirrors.MirrorType
import org.mirah.jvm.mirrors.BytecodeMirror
import org.mirah.jvm.mirrors.Member
import org.mirah.jvm.types.JVMMethod
import org.mirah.jvm.types.JVMField
import org.mirah.jvm.types.JVMTypeUtils
import static org.mirah.jvm.types.JVMTypeUtils.*
import org.mirah.jvm.mirrors.ResolvedCall
import org.mirah.jvm.mirrors.Member
import org.mirah.jvm.types.JVMField
import org.mirah.jvm.types.MemberKind
import org.mirah.jvm.compiler.casesupport.SwitchCompiler
import org.mirah.jvm.compiler.casesupport.EnumValue
import java.util.List
import java.util.regex.Pattern

interface InnerClassCompiler
  def context:Context; end
  # compile inner class from AST and add it to inner classes
  def compileInnerClass(node:ClassDefinition, method:AsmMethod):void; end
  # add inner compiler
  def addInnerClass(compiler:InnerClassCompiler):void; end
  # Class FQDN this instance provide bytes
  def internal_name:String;end
  # Class data byte array
  def getBytes:byte[];end
  # Collection of InnerClassesCompilers generated implicitly by this class compiler
  def innerClasses:Collection;end
end

class MethodCompiler < BaseCompiler

  REGEXP_FLAGS = {
      'i' => Pattern.CASE_INSENSITIVE,
      'd' => Pattern.UNIX_LINES,
      'm' => Pattern.MULTILINE,
      's' => Pattern.DOTALL,
      'u' => Pattern.UNICODE_CASE,
      'x' => Pattern.COMMENTS,
      'U' => Pattern.UNICODE_CHARACTER_CLASS
  }

  def self.initialize:void
    @@log = Logger.getLogger(MethodCompiler.class.getName)
  end
  def initialize(compiler:InnerClassCompiler, klass:JVMType, flags:int, name:String)
    super(compiler.context)
    @flags = flags
    @name = name
    @locals = {}
    @args = {}
    @klass = klass
    @classCompiler = compiler
    # used to generate switch locals
    @caseLevel = 0
  end
  
  def isVoid
    @descriptor.getDescriptor.endsWith(")V")
  end
  
  def isStatic
    (@flags & Opcodes.ACC_STATIC) != 0
  end
  
  def bytecode
    @builder
  end
  
  def compile(cv:ClassVisitor, mdef:MethodDefinition):void
    @@log.fine "Compiling method #{mdef.name.identifier}"
    @builder = createBuilder(cv, mdef)
    anno_compiler = context[AnnotationCompiler]
    anno_compiler.compile(mdef.annotations, @builder)
    anno_compiler.compile(mdef.arguments, @builder)
    isExpression = isVoid() ? nil : Boolean.TRUE
    if (@flags & (Opcodes.ACC_ABSTRACT | Opcodes.ACC_NATIVE)) == 0
      prepareBinding(mdef)
      @lookingForDelegate = mdef.kind_of?(ConstructorDefinition)
      compileBody(mdef.body, isExpression, @returnType)
      body_position = if mdef.body_size > 0
        mdef.body(mdef.body_size - 1).position
      else
        mdef.body.position
      end
      returnValue(mdef)
    end
    @builder.endMethod
    @@log.fine "Finished method #{mdef.name.identifier}"
  end

  def compile(node:Node)
    visit(node, Boolean.TRUE)
  end

  def collectArgNames(mdef:MethodDefinition, bytecode:Bytecode):void
    args = mdef.arguments
    unless isStatic
      bytecode.declareArg('this', @selfType)
    end
    args.required_size.times do |a|
      arg = args.required(a)
      type = getInferredType(arg)
      bytecode.declareArg(arg.name.identifier, type)
    end
    args.optional_size.times do |a|
      optarg = args.optional(a)
      type = getInferredType(optarg)
      bytecode.declareArg(optarg.name.identifier, type)
    end
    if args.rest
      type = getInferredType(args.rest)
      bytecode.declareArg(args.rest.name.identifier, type)
    end
    args.required2_size.times do |a|
      arg = args.required2(a)
      type = getInferredType(arg)
      bytecode.declareArg(arg.name.identifier, type)
    end
  end

  def createBuilder(cv:ClassVisitor, mdef:MethodDefinition)
    type = getInferredType(mdef)

    if @name.endsWith("init>") || ":unreachable".equals(type.returnType.name)
      @returnType = typer.type_system.getVoidType.resolve:JVMType
    else
      @returnType = type.returnType:JVMType
    end

    @descriptor = methodDescriptor(@name, @returnType, type.parameterTypes)
    @selfScope = getScope(mdef)
    @selfType = @selfScope.selfType.resolve:JVMType
    superclass = @selfType.superclass
    @superclass = superclass || findType("java.lang.Object")
    builder = Bytecode.new(@flags, @descriptor, cv, mdef.findAncestor(Script.class).position.source)
    collectArgNames(mdef, builder)
    builder
  end

  def selfType:JVMType
    @selfType
  end

  def selfScope:Scope
    @selfScope
  end

  def prepareBinding(mdef:MethodDefinition):void
    scope = getIntroducedScope(mdef)
    type = scope.binding_type:JVMType
    if type
      # Figure out if we need to create a binding or if it already exists.
      # If this method is inside a ClosureDefinition, the binding is stored
      # in a field. Otherwise, this is the method enclosing the closure,
      # and it needs to create the binding.
      shouldCreateBinding = mdef.findAncestor(ClosureDefinition.class).nil?
      if shouldCreateBinding
        @builder.newInstance(type.getAsmType)
        @builder.dup
        args = AsmType[0]
        @builder.invokeConstructor(type.getAsmType, AsmMethod.new("<init>", AsmType.getType("V"), args))
        @builder.arguments.each do |arg: LocalInfo|
          # Save any captured method arguments into the binding
          if scope.isCaptured(arg.name)
            @builder.dup
            @builder.loadLocal(arg.name)
            @builder.putField(type.getAsmType, arg.name, arg.type)
          end
        end
      else
        @builder.loadThis
        @builder.getField(@selfType.getAsmType, 'binding', type.getAsmType)
      end
      @bindingType = type
      @binding = @builder.newLocal(type.getAsmType)
      @builder.storeLocal(@binding, type.getAsmType)
    end
  end
  
  def recordPosition(position:Position, atEnd:boolean=false)
    @builder.recordPosition(position, atEnd)
  end
  
  def defaultValue(type:JVMType)
    if isPrimitive(type)
      if 'long'.equals(type.name)
        @builder.push((0):long)
      elsif 'double'.equals(type.name)
        @builder.push((0):double)
      elsif 'float'.equals(type.name)
        @builder.push((0):float)
      else
        @builder.push(0)
      end
    else
      @builder.push(nil:String)
    end
  end
  
  def visitFixnum(node, expression)
    if expression
      isLong = "long".equals(getInferredType(node).name)
      recordPosition(node.position)
      if isLong
        @builder.push(node.value)
      else
        @builder.push((node.value):int)
      end
    end
  end
  def visitFloat(node, expression)
    if expression
      isFloat = "float".equals(getInferredType(node).name)
      recordPosition(node.position)
      if isFloat
        @builder.push((node.value):float)
      else
        @builder.push(node.value)
      end
    end
  end
  def visitBoolean(node, expression)
    if expression
      recordPosition(node.position)
      @builder.push(node.value ? 1 : 0)
    end
  end
  def visitCharLiteral(node, expression)
    if expression
      recordPosition(node.position)
      @builder.push(node.value)
    end
  end
  def visitSimpleString(node, expression)
    if expression
      recordPosition(node.position)
      @builder.push(node.value)
    end
  end
  def visitNull(node, expression)
    value = nil:String
    if expression
      recordPosition(node.position)
      @builder.push(value)
    end
  end
  
  def visitSuper(node, expression)
    @lookingForDelegate = false
    @builder.loadThis
    paramTypes = LinkedList.new
    node.parameters_size.times do |i|
      param = node.parameters(i)
      compile(param)
      paramTypes.add(getInferredType(param))
    end
    recordPosition(node.position)
    result = getInferredType(node)

    target = nil:MirrorType
    method = nil:JVMMethod

    if @name.equals 'initialize' or @name.endsWith 'init>'
       # handle constructors
       target = @superclass
       method = if result.kind_of?(CallType)
         result:CallType.member
       else
         @superclass.getMethod(@name, paramTypes)
       end
    else
      # assume order: superclass, interface1, interface2 etc
      @klass:MirrorType.directSupertypes.each do |type:MirrorType|
        method = findSameMethod(type, @name, paramTypes, @flags)
        if method
          target = type
          break
        end
      end
    end

    if method == nil or target == nil
     reportError("No method #{@name} params: #{paramTypes} found for super call", node.position)
    end

    @builder.invokeSpecial(target.getAsmType, methodDescriptor(method))
    if expression && isVoid
      @builder.loadThis
    elsif expression.nil? && !isVoid
      @builder.pop(@returnType)
    end
  end
  
  def visitLocalAccess(local, expression)
    if expression
      recordPosition(local.position)
      name = local.name.identifier

      proper_name = scoped_name(containing_scope(local), name)

      if @bindingType != nil && getScope(local).isCaptured(name)
        @builder.loadLocal(@binding)
        @builder.getField(@bindingType.getAsmType, proper_name, getInferredType(local).getAsmType)
      else
        @builder.loadLocal(proper_name)
      end
    end
  end

  def visitLocalAssignment(local, expression)
    name = local.name.identifier
    isCaptured = @bindingType != nil && getScope(local).isCaptured(name)

    if isCaptured
      @builder.loadLocal(@binding)
    end
    future = typer.type_system.getLocalType(
        getScope(local), name, local.position)
    reportError("error type found by compiler #{future.resolve}", local.position) if future.resolve.kind_of? ErrorType

    type:JVMType = future.resolve
    valueType = getInferredType(local.value)
    if local.value.kind_of?(NodeList)
      compileBody(local.value:NodeList, Boolean.TRUE, type)
      valueType = type
    else
      visit(local.value, Boolean.TRUE)
    end

    if expression
      if isCaptured
        @builder.dupX1(valueType)
      else
        @builder.dup(valueType)
      end
    end

    @builder.convertValue(valueType, type)
    recordPosition(local.position)

    proper_name = scoped_name(containing_scope(local), name)
    if isCaptured
      @builder.putField(@bindingType.getAsmType, proper_name, type.getAsmType)
    else
      @builder.storeLocal(proper_name, type)
    end

  end
  
  def containing_scope(node: Named): Scope
    scope = getScope node
    name = node.name.identifier
    containing_scope scope, name
  end

  def containing_scope(node: RescueClause): Scope
    scope = getScope node.body
    name = node.name.identifier
    containing_scope scope, name
  end
  def containing_scope(scope: Scope, name: String)
    while _has_scope_something scope, name
      scope = scope.parent
    end
    scope
  end

  def _has_scope_something(scope: Scope, name: String): boolean
    not_shadowed = !scope.shadowed?(name)
    not_shadowed && !scope.parent.nil? && scope.parent.hasLocal(name)
  end

  def scoped_name scope: Scope, name: String
    if scope.shadowed? name
      "#{name}$#{System.identityHashCode(scope)}"
    else
      name
    end
  end

  def visitFunctionalCall(call, expression)
    reportError("call to #{call.name.identifier}'s block has not been converted to a closure",  call.position) if call.block

    name = call.name.identifier

    # if this is the first line of a constructor, a call to 'initialize' is really a call to another
    # constructor.
    if @lookingForDelegate && name.equals("initialize")
      name = "<init>"
    end
    @lookingForDelegate = false

    compiler = CallCompiler.new(self, @builder, call.position, call.target, name, call.parameters, getInferredType(call))
    compiler.compile(expression != nil)
  end
  
  def visitCall(call, expression)
    reportError("call to #{call.name.identifier}'s block has not been converted to a closure", call.position) if call.block

    compiler = CallCompiler.new(self, @builder, call.position, call.target, call.name.identifier, call.parameters, getInferredType(call))
    compiler.compile(expression != nil)
  end

  def compileIfBody(body:NodeList, expression:Object, type:JVMType):void
    compileBody(body, expression, type)
    bodyType = getInferredType(body)
    if needConversion(bodyType, type) && expression
      @builder.convertValue(bodyType, type)
    end
  end

  def compileBody(node:NodeList, expression:Object, type:JVMType):void
    if node.size == 0
      if expression
        defaultValue(type)
      else
        @builder.visitInsn(Opcodes.NOP)
      end
    else
      visitNodeList(node, expression)
    end
  end
  
  def visitIf(node, expression)
    elseLabel = @builder.newLabel
    endifLabel = @builder.newLabel
    compiler = ConditionCompiler.new(self, node, @builder)
    type = getInferredType(node)
    
    need_then = !expression.nil? || node.body_size > 0
    need_else = !expression.nil? || node.elseBody_size > 0

    if need_then
      compiler.negate
      compiler.compile(node.condition, elseLabel)
      compileIfBody(node.body, expression, type)
      @builder.goTo(endifLabel)
    else
      compiler.compile(node.condition, endifLabel)
    end
    
    @builder.mark(elseLabel)
    if need_else
      compileIfBody(node.elseBody, expression, type)
    end
    recordPosition(node.position, true)
    @builder.mark(endifLabel)
  end

  def visitImplicitNil(node, expression)
    if expression
      defaultValue(getInferredType(node))
    end
  end
  
  def visitReturn(node, expression)
    compile(node.value) unless isVoid
    handleEnsures(node, MethodDefinition.class)
    type = getInferredType node.value
    @builder.convertValue(type, @returnType) unless isVoid || type.nil?
    @builder.returnValue
  end
  
  def visitCast(node, expression)
    compile(node.value)
    from = getInferredType(node.value)
    to = getInferredType(node)
    if needConversionOnCast(from, to)
      @builder.cast(from.getAsmType, to.unbox.getAsmType)
      @builder.box(to.unbox.getAsmType)
    elsif needConversionOnCast(to, from)
      @builder.unbox(from.unbox.getAsmType)
      @builder.cast(from.unbox.getAsmType, to.getAsmType)
    else
      @builder.convertValue(from, to)
    end
    @builder.pop(to) unless expression
  end
  
  def visitFieldAccess(node, expression)
    klass = @selfType.getAsmType
    name = node.name.identifier
    reportError("instance field #{name} accessed in static context", node.position)  if isStatic() and  !node.isStatic
    type = getInferredType(node)
    isStatic = node.isStatic || self.isStatic
    if isStatic
      recordPosition(node.position)
      @builder.getStatic(klass, name, type.getAsmType)
    else
      @builder.loadThis
      recordPosition(node.position)
      @builder.getField(klass, name, type.getAsmType)
    end
    unless expression
      @builder.pop(type)
    end
  end
  
  def visitFieldAssign(node, expression)
    klass = @selfType.getAsmType
    name = node.name.identifier
    reportError("field name #{name} ends with =", node.position)  if name.endsWith("=")
    reportError("instance field #{name} assigned in static context", node.position)  if isStatic() &&  !node.isStatic
    isStatic = node.isStatic || self.isStatic
    type = @klass.getDeclaredField(node.name.identifier).returnType
    @builder.loadThis unless isStatic
    compile(node.value)
    valueType = getInferredType(node.value)
    if expression
      if isStatic
        @builder.dup(valueType)
      else
        @builder.dupX1(valueType)
      end
    end
    @builder.convertValue(valueType, type)
    
    recordPosition(node.position)
    if isStatic
      @builder.putStatic(klass, name, type.getAsmType)
    else
      @builder.putField(klass, name, type.getAsmType)
    end
  end
  
  def visitEmptyArray(node, expression)
    compile(node.size)
    recordPosition(node.position)
    type = getInferredType(node).getComponentType
    @builder.newArray(type.getAsmType)
    @builder.pop unless expression
  end
  
  def visitAttrAssign(node, expression)
    compiler = CallCompiler.new(
        self, @builder, node.position, node.target,
        "#{node.name.identifier}_set", [node.value], getInferredType(node))
    compiler.compile(expression != nil)
  end
  
  def visitStringConcat(node, expression)
    visit(node.strings, expression)
  end
  
  def visitStringPieceList(node, expression)
    if node.size == 0
      if expression
        recordPosition(node.position)
        @builder.push("")
      end
    elsif node.size == 1 && node.get(0).kind_of?(SimpleString)
      visit(node.get(0), expression)
    else
      compiler = StringCompiler.new(self)
      compiler.compile(node, expression != nil)
    end
  end
  
  def visitRegex(node, expression)
    compile(node.strings)
    flag = 0
    if node.options
      options = node.options.identifier ? node.options.identifier : ''
      options.length.times do |i|
        f = "#{options.charAt(i)}"
        option = REGEXP_FLAGS[f]
        unless option
          reportError "Unsupported regexp Pattern flag #{f}. Valid flags are: #{REGEXP_FLAGS.keySet}", node.position
        else
          flag = flag | option:int
        end
      end
    end
    @builder.push(flag)
    recordPosition(node.position)
    pattern = findType("java.util.regex.Pattern")
    @builder.invokeStatic(pattern.getAsmType, methodDescriptor("compile", pattern, [findType('java.lang.String'), findType('int')]))
    @builder.pop unless expression
  end
  
  def visitNot(node, expression)
    visit(node.value, expression)
    if expression
      recordPosition(node.position)
      done = @builder.newLabel
      elseLabel = @builder.newLabel
      type = getInferredType(node.value)
      if isPrimitive(type)
        @builder.ifZCmp(GeneratorAdapter.EQ, elseLabel)
      else
        @builder.ifNull(elseLabel)
      end
      @builder.push(0)
      @builder.goTo(done)
      @builder.mark(elseLabel)
      @builder.push(1)
      @builder.mark(done)
    end
  end
  
  def returnValue(mdef:MethodDefinition)
    body = mdef.body
    type = getInferredType(body)
    unless isVoid || type.nil? || @returnType.assignableFrom(type)
      # TODO this error should be caught by the typer
      body_position = if body.size > 0
        body.get(body.size - 1).position
      else
        body.position
      end
      reportError("Invalid return type #{type.name}, expected #{@returnType.name}", body_position)
    end
    @builder.convertValue(type, @returnType) unless isVoid || type.nil?
    @builder.returnValue
  end
  
  def visitSelf(node, expression)
    if expression
      recordPosition(node.position)
      @builder.loadThis
    end
  end

  def visitImplicitSelf(node, expression)
    if expression
      recordPosition(node.position)
      @builder.loadThis
    end
  end
  
  def visitLoop(node, expression)
    old_loop = @loop
    @loop = LoopCompiler.new(@builder)
    
    visit(node.init, nil)
    
    predicate = ConditionCompiler.new(self, node, @builder)
    
    preLabel = @builder.newLabel
    unless node.skipFirstCheck
      @builder.mark(@loop.getNext) unless node.post_size > 0
      # Jump out of the loop if the condition is false
      predicate.negate unless node.negative
      predicate.compile(node.condition, @loop.getBreak)
      # un-negate the predicate
      predicate.negate
    end
      
    @builder.mark(preLabel)
    visit(node.pre, nil)
    
    @builder.mark(@loop.getRedo)
    visit(node.body, nil) if node.body
    
    if node.skipFirstCheck || node.post_size > 0
      @builder.mark(@loop.getNext)
      visit(node.post, nil)
      # Loop if the condition is true
      predicate.negate if node.negative
      predicate.compile(node.condition, preLabel)
    else
      @builder.goTo(@loop.getNext)
    end
    @builder.mark(@loop.getBreak)
    recordPosition(node.position, true)

    # loops always evaluate to null
    @builder.pushNil if expression
  ensure
    @loop = old_loop
  end
  
  def visitBreak(node, expression)
    if @loop
      handleEnsures(node, Loop.class)
      @builder.goTo(@loop.getBreak)
    else
      reportError("Break outside of loop", node.position)
    end
  end
  
  def visitRedo(node, expression)
    if @loop
      handleEnsures(node, Loop.class)
      @builder.goTo(@loop.getRedo)
    else
      reportError("Redo outside of loop", node.position)
    end
  end
  
  def visitNext(node, expression)
    if @loop
      handleEnsures(node, Loop.class)
      @builder.goTo(@loop.getNext)
    else
      reportError("Next outside of loop", node.position)
    end
  end
  
  def visitArray(node, expression)
    @arrays ||= ArrayCompiler.new(self, @builder)
    @arrays.compile(node)
    @builder.pop unless expression
  end
  
  def visitHash(node, expression)
    @hashes ||= HashCompiler.new(self, @builder)
    @hashes.compile(node)
    @builder.pop unless expression
  end
  
  def visitRaise(node, expression)
    compile(node.args(0))
    recordPosition(node.position)
    @builder.throwException
  end
  
  def visitRescue(node, expression)
    start = @builder.mark
    start_offset = @builder.instruction_count
    bodyEnd = @builder.newLabel
    bodyIsExpression = if expression.nil? || node.elseClause.size > 0
      nil
    else
      Boolean.TRUE
    end
    visit(node.body, bodyIsExpression)
    end_offset = @builder.instruction_count
    @builder.mark(bodyEnd)
    visit(node.elseClause, expression) if node.elseClause.size > 0
    
    # If the body was empty, it can't throw any exceptions
    # so we must not emit a try/catch.
    unless start_offset == end_offset
      done = @builder.newLabel
      @builder.goTo(done)
      node.clauses_size.times do |clauseIndex|
        clause = node.clauses(clauseIndex)
        clause.types_size.times do |typeIndex|
          type = getInferredType(clause.types(typeIndex))
          @builder.catchException(start, bodyEnd, type.getAsmType)
        end
        if clause.name
          recordPosition(clause.name.position)
          proper_name = scoped_name(containing_scope(clause), clause.name.identifier)

          @builder.storeLocal(proper_name, AsmType.getType('Ljava/lang/Throwable;'))
        else
          @builder.pop
        end
        compileBody(clause.body, expression, getInferredType(node))
        @builder.goTo(done)
      end
      @builder.mark(done)
    end
  end
  
  def handleEnsures(node:Node, klass:Class):void
    while node.parent
      visit(node:Ensure.ensureClause, nil) if node.kind_of?(Ensure)
      break if klass.isInstance(node)
      node = node.parent
    end
  end
  
  def visitEnsure(node, expression)
    start = @builder.mark
    bodyEnd = @builder.newLabel
    start_offset = @builder.instruction_count
    visit(node.body, expression)
    end_offset = @builder.instruction_count
    @builder.mark(bodyEnd)
    visit(node.ensureClause, nil)
    
    # If the body was empty, it can't throw any exceptions
    # so we must not emit a try/catch.
    unless start_offset == end_offset
      done = @builder.newLabel
      @builder.goTo(done)
      @builder.catchException(start, bodyEnd, nil)
      visit(node.ensureClause, nil)
      @builder.throwException
      @builder.mark(done)
    end
  end
  
  def visitNoop(node, expression)
  end
  
  def visitClassDefinition(node, expression)
    @classCompiler.compileInnerClass(node, @descriptor)
  end

  def visitEnumDefinition(node, expression)
    visitClassDefinition(node, expression)
  end

  def visitClosureDefinition(node, expression)
    visitClassDefinition(node, expression)
  end
  
  def visitBindingReference(node, expression)
    @builder.loadLocal(@binding) if expression
  end

  def visitCase(node, expression)
    # note! verification on when, else and conditions are induced by parser
    type = getInferredType(node)
    # TODO boxing/unboxing?
    # TODO implement for numerics, string and Class(TypeRef?) condition as java switch statement!
    # TODO support multiple WhenClasure.candidates
    condType = getInferredType(node.condition)
    SwitchCompiler.new(self, condType, type, @builder, @caseLevel+=1).compile(node, expression)
    @caseLevel-=1
  end

  def self.findSameMethod(type:MirrorType, name: String, params: List, flags:int):Member
    if type.kind_of? BytecodeMirror
      method = type.getMethod(name, params):Member
      if method and checkSuperFlags(method, flags)
        @@log.fine "Method #{name}(#{params}) found for #{type}"
        return method
      end
    else
      type:MirrorType.getDeclaredMethods(name).each do |member:Member|
        if member.argumentTypes.equals(params) and checkSuperFlags(member, flags)
          @@log.fine "Method #{name}(#{params}) found for #{type}"
          return member
        end
      end
    end

    type.directSupertypes.each do |type:MirrorType|
      method = findSameMethod(type, name, params, flags)
      if method
        return method
      end
    end

    return nil
  end

  # check not abstract and same value for static mask
  def self.checkSuperFlags(member:Member, flags:int):boolean
     _flags = member.flags
     _flags & Opcodes.ACC_ABSTRACT == 0 and  (flags & Opcodes.ACC_STATIC == _flags & Opcodes.ACC_STATIC)
  end

  def needConversionOnCast(from: JVMType, to: JVMType)
    return false unless from and to
    return false if from.equals(to)
    return false if from.getAsmType.getSort == AsmType.VOID
    return false if to.getAsmType.getSort == AsmType.VOID
    isPrimitive(from) && !isPrimitive(to) && supportBoxing(to)
  end

  def needConversion(from: JVMType, to: JVMType)
    return false unless from and to
    return false if from.equals(to)
    return false if from.getAsmType.getSort == AsmType.VOID
    return false if to.getAsmType.getSort == AsmType.VOID
    if isPrimitive(to) && isPrimitive(from)
      return !to.equals(from)
    elsif isPrimitive(from) && !isPrimitive(to)
      # to - could be intersection type as in:
      # x = true ? 1 : 2:Long  -> x is inferred as an IntersectionType
      return true if(to.unbox != nil)
      if isDeclared(to) && to.assignableFrom(from.box)
        puts "new true: #{to} #{to.getClass} #{from}"
        return true
      else
        return false
      end
    elsif isPrimitive(to) && !isPrimitive(from)
      from.unbox != nil
    else
      false
    end
  end

  def readConstValue(node:Node):Object
    nodeValue = typer.readConstValue node
    return nodeValue if nodeValue

    type = getInferredType(node)
    member = if type.kind_of? ResolvedCall
      type:ResolvedCall.member
    elsif node.kind_of?(FieldAccess) && node:FieldAccess.isStatic
      # static field access in the same class
      @selfType.getDeclaredField(node:FieldAccess.name.identifier)
    end

    if member && member.kind == MemberKind.STATIC_FIELD_ACCESS
      if isEnum(member.declaringClass) && member.declaringClass == member.returnType
        return EnumValue.new member.name, member.declaringClass
      else
        return  member:JVMField.constantValue
      end
    end

    return nil
  end

  def addInnerClass(compiler:InnerClassCompiler):void
    @classCompiler.addInnerClass(compiler)
  end

end