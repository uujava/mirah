package org.mirah.typer

import mirah.lang.ast.*
import java.util.Collections
import java.util.LinkedHashMap
import java.util.List

class EnumRewriter < NodeScanner

  def initialize(typer: Typer)
    @typer = typer

  end

  def rewrite(edef: EnumDefinition):ClassDefinition
    order = 0
    values = LinkedHashMap.new
    @enum_type_name = edef.name:TypeName
    @enum_position = edef.position
    @constructors = []
    rewrite_common(edef)
    to_remove = []
    edef.constants.each do |const:Node|
      params = []
      const_type = @enum_type_name
      if isConst(const)
        const_name = const:Named.name
        # edef constructor parms:
        params.add(const_name)
        params.add(Fixnum.new(order))
        if const.kind_of? FunctionalCall
          fconst = const:FunctionalCall
          fconst.parameters.each { |p| params.add p }
          if fconst.block
            # create inner class with body and copy constructors definitions calling super synthetic constructor
            # generates package protected synthetic constructors
            # it generates more constructor then needed, but that simplify all stuff
            inner_name = "#{@enum_type_name.typeref.name}$#{@typer.scopeOf(edef).temp('Inner')}"
            add_inner_class(edef, inner_name, fconst.block)
            const_type = Constant.new(const.position, SimpleString.new(const.position, inner_name))
          end
        end
        value = Call.new(const.position, const_type, SimpleString.new('new'), params, nil)
        const_field = FieldAssign.new(
                       const.position,
                       const_name,
                       value,
                       [],
                       [Modifier.new('PUBLIC'), Modifier.new('FINAL'), Modifier.new('ENUM')],
                       nil)
        const_field.isStatic = true
        if values.get(const_name.identifier)
          reportError "Duplicate constant name #{const_name.identifier}", const
        else
          values.put(const_name.identifier, const_field)
          to_remove << const
        end
      else
       reportError "Unsupported enum constant expression #{const}", const
       next
      end
      order += 1
    end
    to_remove.each do |node:Node|
      edef.constants.removeChild node
    end
    rewrite_initializer(values)
    edef
  end

  def enterConstructorDefinition(mdef, expression)
    @constructors << mdef
    false
  end

  def enterDefault(node, expression)
    false
  end

  def enterNodeList(node, expression)
    true
  end

  def enterStaticMethodDefinition(mdef, expression)
    # static initializer
    if mdef.name.identifier == 'initialize' && mdef.arguments.required_size == 0
      @initializer_body = mdef.body
    end
    false
  end

  # constructor and find class initializer
  private def rewrite_common(edef:EnumDefinition):void
    edef.body.accept(self, nil)
    unless @initializer_body
      initializer = StaticMethodDefinition.new(
              edef.position,
              SimpleString.new(edef.position, 'initialize'),
              Arguments.new(edef.position,
                       Collections.emptyList,
                       Collections.emptyList,
                       nil,
                       Collections.emptyList,
                       nil),
              SimpleString.new(edef.position, 'void'),
              [],
              [])
      @initializer_body = initializer.body
      edef.body.add initializer
    end
    add_value_of edef
    add_values edef
    if @constructors.isEmpty
      args = Arguments.new(edef.position,
                [],
                Collections.emptyList,
                nil,
                Collections.emptyList,
                nil)
      constructor = ConstructorDefinition.new(
              SimpleString.new('initialize'), args,
              SimpleString.new('void'), [], nil, nil)
      edef.body.add constructor
      @constructors << constructor
    end
    @constructors.each do |constructor:ConstructorDefinition|
      rewrite_constructor(constructor)
    end
  end

  private def rewrite_initializer(values: LinkedHashMap):void
    order = 0
    init_body = NodeList.new(@initializer_body.position)
    values_assign = FieldAssign.new(@enum_position,
                         SimpleString.new(@enum_position, '$VALUES'),
                         EmptyArray.new(@enum_position, @enum_type_name, Fixnum.new(values.size)),
                         [],
                         [Modifier.new('PRIVATE'), Modifier.new('FINAL'), Modifier.new('SYNTHETIC')],
                         nil)
    values_assign.isStatic = true
    init_body.add values_assign
    values.each do | name:String, node:Node|
      init_body.add node
      init_body.add Call.new(@enum_position,
               FieldAccess.new(@enum_position, SimpleString.new('$VALUES'), true),
               SimpleString.new(@enum_position, '[]='),
               [Fixnum.new(@enum_position, order), FieldAccess.new(@enum_position, SimpleString.new(name), true)],
               nil
               )
      order += 1
    end
    @initializer_body.insert 0, init_body
  end

  private def rewrite_constructor(mdef:ConstructorDefinition):void
    args = mdef.arguments.required
    args.insert 0, RequiredArgument.new(args.position, SimpleString.new('$x2'), SimpleString.new(args.position, 'int'))
    args.insert 0, RequiredArgument.new(args.position, SimpleString.new('$x1'), SimpleString.new(args.position, 'java.lang.String'))
    mdef.body.insert 0, Super.new(mdef.body.position, [LocalAccess.new(SimpleString.new('$x1')), LocalAccess.new(SimpleString.new('$x2'))], nil)
    if mdef.modifiers_size > 0
      reportError("enum constructors implicitly private", mdef.modifiers)
    end
    mdef.modifiers = ModifierList.new(mdef.position, [Modifier.new('PRIVATE')])
  end

  private def reportError(msg:String, node:Node)
    @typer.learnType(node, ErrorType.new([[msg, node.position]]))
  end

  private def add_value_of(edef:EnumDefinition):void
    value_of = StaticMethodDefinition.new(
                 edef.position,
                 SimpleString.new(edef.position, 'valueOf'),
                 Arguments.new(edef.position,
                          [RequiredArgument.new(edef.position,
                                                SimpleString.new('name'),
                                                SimpleString.new('java.lang.String'))],
                          Collections.emptyList,
                          nil,
                          Collections.emptyList,
                          nil),
                 @enum_type_name,
                 [Call.new(edef.position,
                           TypeRefImpl.new('java.lang.Enum', false, false, edef.position),
                           SimpleString.new('valueOf'),
                           [Call.new(@enum_type_name.typeref, SimpleString.new('class'),[],nil),
                            LocalAccess.new(SimpleString.new('name'))], nil)
                  ],
                 [])
    edef.body.add(value_of)
  end

  private def add_values(edef:EnumDefinition):void
    values = StaticMethodDefinition.new(
                 edef.position,
                 SimpleString.new(edef.position, 'values'),
                 Arguments.new(edef.position,
                          Collections.emptyList,
                          Collections.emptyList,
                          nil,
                          Collections.emptyList,
                          nil),
                 TypeRefImpl.new(@enum_type_name.typeref.name, true, false, edef.position),
                 [Cast.new(TypeRefImpl.new(@enum_type_name.typeref.name, true, false, edef.position),
                           Call.new(edef.position,
                           FieldAccess.new(@enum_position, SimpleString.new('$VALUES'), true),
                           SimpleString.new('clone'),
                           [], nil))
                  ],
                 [])
    edef.body.add(values)
  end

 # constants are ast Constants like:
 # A, B, C
 # or ast VCall
 # a, b, c
 # or ast FunctionalCall like:
 # A('x'), B('x') { def foo(); 1; end}, C { def foo(); 2; end}
  private def isConst(const:Node):boolean
    const.kind_of?(FunctionalCall) || const.kind_of?(Constant) || const.kind_of?(VCall)
  end

  private def add_inner_class(parent:EnumDefinition, name:String, body:Block):void
    unless @synthetic_param_type
     # we need this to generate protected synthetic outer constructor and call it from inner one
     @synthetic_param_type = name
     add_synthetic_constructors(parent, name)
    end
    body_nodes = []
    body.body.each do |n:Node|
      body_nodes << n.clone:Node
    end
    # TODO validate no constructors in the body
    inner_def = ClassDefinition.new(body.position,
                      SimpleString.new(name),
                      @enum_type_name,
                      body_nodes, # body
                      Collections.emptyList, # interfaces
                      [],
                      [Modifier.new('DEFAULT'), Modifier.new('FINAL')])
    @constructors.each do |mdef:ConstructorDefinition|
      # here we have all rewritten constructors from outer
      # clone and add
      super_args = []
      mdef.arguments.required.each do |arg:RequiredArgument|
        super_args << LocalAccess.new(arg.position, arg.name)
      end
      # this will route super to synthetic protected constructor
      super_args << Cast.new(TypeRefImpl.new(@synthetic_param_type, false, false, mdef.arguments.required.position), Null.new)
      mdef = create_constructor(mdef.position,
                         mdef.arguments,
                         Collections.emptyList,
                         [Super.new(mdef.body.position, super_args, nil)],
                         [Modifier.new('DEFAULT')])
      inner_def.body.add mdef
    end
    parent.body.add inner_def
  end

  private def add_synthetic_constructors(parent:EnumDefinition, synthetic_param_type:String):void
    if synthetic_param_type
      @constructors.each do |mdef:ConstructorDefinition|
        body_clone = []
        mdef.body.each do |n:Node|
          body_clone << n.clone
        end
        constructor = create_constructor(mdef.position,
            mdef.arguments,
            [RequiredArgument.new(mdef.position, SimpleString.new('$x3'), SimpleString.new(synthetic_param_type))],
            body_clone,
            [Modifier.new('SYNTHETIC')])
        parent.body.add constructor
      end
    end
  end

  def create_constructor(position:Position, original_args:Arguments, additional_args:List, body:List, modifiers:List):ConstructorDefinition
    clone_args = []
    original_args.required.each do |arg:RequiredArgument|
      clone_args << arg.clone
    end
    clone_args.addAll additional_args
    args = Arguments.new(position,
             clone_args,
             Collections.emptyList,
             nil,
             Collections.emptyList,
             nil)
    constructor = ConstructorDefinition.new(
            SimpleString.new('initialize'),
            args,
            SimpleString.new('void'),
            body,
            [],
            modifiers)
  end
end