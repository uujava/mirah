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

package org.mirah.builtins

import mirah.lang.ast.*

import org.mirah.macros.anno.ExtensionsRegistration

$ExtensionsRegistration[['java.lang.Object']]
class ObjectExtensions

  macro def ==(node)
    # During the transition, alias == to === inside equals method definitions
    mdef = @call.findAncestor(MethodDefinition.class):MethodDefinition
    if mdef && mdef.name.identifier.equals("equals")
      if @call.target.kind_of?(Self) || node.kind_of?(Self)
        System.out.println("WARNING: == is now an alias for Object#equals(), === is now used for identity.\nThis use of == with self in equals() definition may cause a stack overflow in next release!#{mdef.position.source.name}:")
        source = @mirah.typer.sourceContent(mdef)
        s = source.split("\n")
        # last end has right whitespace, but def doesn't
        whitespace = s[s.length - 1].substring(0, s[s.length - 1].indexOf("end"))
        System.out.println("#{whitespace}#{source}")
        return quote {`@call.target` === `node`}
      end
    end

    left  = gensym
    right = gensym
    quote do
      `left`  = `@call.target`
      `right` = `node`
       if `left` === nil
         `right` === nil
       else
         `left`.equals `right`
       end
    end
  end

  ## TODO handle the negation st def == will be called
  macro def !=(node)
    # TODO this doesn't work, but should
    #quote { ( `@call.target`.nil? && `node`.nil? ) || !`@call.target`.equals(`node`) }

    quote { !(`@call.target` == `node`)}
  end
  
  macro def tap(block:Block)
    x = gensym
    quote do
      `x` = `@call.target`
      `block.arguments.required(0).name.identifier` = `x`
      `block.body`
      `x`
    end
  end

  macro def puts(node)
    quote {System.out.println(` [node] `)}
  end
  macro def self.puts(node)
    quote {System.out.println(` [node] `)}
  end

  macro def puts()
    quote {System.out.println()}
  end
  macro def self.puts()
    quote {System.out.println()}
  end

  macro def print(node)
    quote {System.out.print(` [node] `)}
  end
  macro def self.print(node)
    quote {System.out.print(` [node] `)}
  end
  macro def loop(block:Block)
    quote { while true do `block.body` end }
  end
  macro def self.loop(block:Block)
    quote { while true do `block.body` end }
  end

  # "protected" on a list of methods
  macro def self.protected_methods(methods_proxy:NodeList)
    import org.mirah.typer.ProxyNode
    import java.util.LinkedList
    work:LinkedList = LinkedList.new([methods_proxy])

    while !work.isEmpty
      node = work.poll:Node
      if node.kind_of?(MethodDefinition)
        anno = Modifier.new(node.position, 'PROTECTED')
        node:MethodDefinition.modifiers ||= ModifierList.new
        node:MethodDefinition.modifiers.add(anno)
      elsif node.kind_of?(ProxyNode)
        work.add(node:ProxyNode.get(0))
      elsif node.kind_of?(NodeList)
        list = node:NodeList
        i = 0
        while i < list.size
          work.add(list.get(i))
          i+=1
        end
      end
    end
    methods_proxy.get(0).setParent(nil)
    methods_proxy.get(0) # FIXME: if we used methods_proxy instead of methods_proxy.get(0) as return value, then the annotation is not effective
  end

  # "private" on a list of methods
  macro def self.private_methods(methods_proxy:NodeList)
    import org.mirah.typer.ProxyNode
    import java.util.LinkedList
    work:LinkedList = LinkedList.new([methods_proxy])

    while !work.isEmpty
      node = work.poll:Node
      if node.kind_of?(MethodDefinition)
        anno = Modifier.new(node.position, 'PRIVATE')
        node:MethodDefinition.modifiers ||= ModifierList.new
        node:MethodDefinition.modifiers.add(anno)
      elsif node.kind_of?(ProxyNode)
        work.add(node:ProxyNode.get(0))
      elsif node.kind_of?(NodeList)
        list = node:NodeList
        i = 0
        while i < list.size
          work.add(list.get(i))
          i+=1
        end
      end
    end
    methods_proxy.get(0).setParent(nil)
    methods_proxy.get(0) # FIXME: if we used methods_proxy instead of methods_proxy.get(0) as return value, then the annotation is not effective
  end

  macro def self.attr_accessor(hash:Hash)
    args = [hash]
    quote do
      attr_reader `args`
      attr_writer `args`
    end
  end

  macro def self.attr_reader(hash:Hash)
    methods = NodeList.new
    i = 0
    parent = @call.findAncestor ClassDefinition.class
    isInterface = parent && parent.kind_of?(InterfaceDeclaration)
    size = hash.size
    while i < size
      e = hash.get(i)
      i += 1
      method = unless isInterface
        quote do
          def `e.key`:`e.value`  #`
            @`e.key`
          end
        end
      else
        quote do
          def `e.key`:`e.value`;end
        end
      end
      methods.add(method)
    end
    methods
  end

  macro def self.attr_writer(hash:Hash)
    methods = NodeList.new
    i = 0
    size = hash.size
    parent = @call.findAncestor ClassDefinition.class
    isInterface = parent && parent.kind_of?(InterfaceDeclaration)
    while i < size
      e = hash.get(i)
      i += 1
      name = "#{e.key:Identifier.identifier}_set"
      method =  unless isInterface
        method = quote do
          def `name`(value:`e.value`):`e.value`
            @`e.key` = value
          end
        end
      else
        method = quote do
          def `name`(value:`e.value`):`e.value`;end
        end
      end
      methods.add(method)
    end
    methods
  end

  macro def lambda(type:TypeName, block:Block)
    SyntheticLambdaDefinition.new(@call.position, type:TypeName, nil, block)
  end

  macro def self.lambda(type:TypeName, block:Block)
    SyntheticLambdaDefinition.new(@call.position, type:TypeName, nil, block)
  end

  macro def lambda(type:TypeName, *args:Node)
    if args.length == 0 or !args[args.length-1].kind_of? Block
      return ErrorNode.new(@call.position, "Missing block for lambda")
    end
    parameters = []
    i = 0
    while i < args.length-1
      parameters.add args[i]
      i+=1
    end
    SyntheticLambdaDefinition.new(@call.position, type:TypeName, parameters, args[args.length-1]:Block)
  end

  macro def self.lambda(type:TypeName, *args:Node)
    if args.length == 0 or !args[args.length-1].kind_of? Block
      return ErrorNode.new(@call.position, "Missing block for lambda")
    end
    parameters = []
    i = 0
    while i < args.length-1
      parameters.add args[i]
      i+=1
    end
    SyntheticLambdaDefinition.new(@call.position, type:TypeName, parameters, args[args.length-1]:Block)
  end

  macro def synchronize(block:Block)
    monitor_enter = Call.new(block.position, @call.target, SimpleString.new('$monitor_enter'), [], nil)
    monitor_exit  = Call.new(block.position, @call.target, SimpleString.new('$monitor_exit'), [], nil)
    body = block.body
    quote do
      `monitor_enter`
      begin
        `body`
        `monitor_exit`
      rescue Throwable => ex
        while true do
          begin
            `monitor_exit`
            break
          rescue Throwable
          end
        end
        raise ex
      end
    end
  end
end
