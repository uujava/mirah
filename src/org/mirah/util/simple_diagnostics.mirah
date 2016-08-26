package org.mirah.util

import java.util.Arrays
import java.util.HashMap
import java.util.Locale
import javax.tools.Diagnostic.Kind
import javax.tools.DiagnosticListener
import mirah.lang.ast.CodeSource

class SimpleDiagnostics implements DiagnosticListener
  def initialize(color:boolean)
    @newline = /\r?\n/
    @prefixes = HashMap.new
    if color
      @prefixes.put(Kind.ERROR, "\e[1m\e[31mERROR\e[0m: ")
      @prefixes.put(Kind.MANDATORY_WARNING, "\e[1m\e[33mWARNING\e[0m: ")
      @prefixes.put(Kind.WARNING, "\e[1m\e[33mWARNING\e[0m: ")
      @prefixes.put(Kind.NOTE, "")
      @prefixes.put(Kind.OTHER, "")
    else
      @prefixes.put(Kind.ERROR, "ERROR: ")
      @prefixes.put(Kind.MANDATORY_WARNING, "WARNING: ")
      @prefixes.put(Kind.WARNING, "WARNING: ")
      @prefixes.put(Kind.NOTE, "")
      @prefixes.put(Kind.OTHER, "")
    end
  end

  def report(diagnostic)
    source = diagnostic.getSource:CodeSource if diagnostic.getSource.kind_of?(CodeSource)
    position = if source
      String.format("%s:%d:%n", source.name, diagnostic.getLineNumber)
    end
    message = diagnostic.getMessage(Locale.getDefault)
    if source
      buffer = StringBuffer.new(message)
      newline = String.format("%n")
      buffer.append(newline)
      
      target_line = Math.max(0, (diagnostic.getLineNumber - source.initialLine):int)
      start_col = if target_line == 0
        diagnostic.getColumnNumber - source.initialColumn
      else
        diagnostic.getColumnNumber - 1
      end
      start_col = 0 if start_col < 0
      lines = @newline.split(source.contents)
      if target_line < lines.length
        line = lines[target_line]
        buffer.append(line)
        buffer.append(newline)
        space = char[(start_col):int]
        prefix = line.substring(0,start_col:int)
        prefix.length.times do |i|
          c = prefix.charAt(i) 
          if Character.isWhitespace(c)
            space[i] = c
          else
            space[i] = (32):char
          end
        end
        buffer.append(space)
        length = Math.min(diagnostic.getEndPosition - diagnostic.getStartPosition,
                          line.length - start_col)
        underline = char[Math.max(length, 1):int]
        Arrays.fill(underline, (94):char)
        buffer.append(underline)
        message = buffer.toString
      end
    end
    log(diagnostic.getKind, position, message)
  end

  private def log(kind:Kind, position:String, message:String):void
    System.err.println(position) if position
    System.err.print(@prefixes[kind])
    System.err.println(message)
  end
end