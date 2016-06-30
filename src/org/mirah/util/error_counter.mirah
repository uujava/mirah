package org.mirah.util

import java.util.Arrays
import java.util.HashMap
import java.util.Locale
import javax.tools.Diagnostic.Kind
import javax.tools.DiagnosticListener
import mirah.lang.ast.CodeSource

class CompilationFailure < Exception
  def initialize(error_count:int)
    super "Compilation failure: #{error_count} error(s)"
  end
end

class ErrorCounter implements DiagnosticListener

  def initialize(parent:DiagnosticListener)
    @parent = parent
    @max_errors = 20
    @errors = 0
  end

  def setMaxErrors(count:int):void
    @max_errors = count
  end

  def errorCount; @errors; end

  def report(diagnostic)
    @errors += 1 if Kind.ERROR == diagnostic.getKind
    if @parent
      @parent.report(diagnostic) rescue nil
    end
    if @errors > @max_errors && @max_errors > 0
      raise CompilationFailure.new @errors
    end
  end
end