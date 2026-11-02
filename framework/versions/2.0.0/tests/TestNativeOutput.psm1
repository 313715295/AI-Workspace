# Private redirected text output for owned CLI test processes (including PS5).
# Keep the actual Console references: SetOut/SetError may synchronize writers.
$script:NativeOutputWriter=$null
$script:NativeErrorWriter=$null
function Initialize-AiwTestNativeOutput {
    if([Console]::IsOutputRedirected){
        if($null-ne$script:NativeOutputWriter){
            if(-not[object]::ReferenceEquals([Console]::Out,$script:NativeOutputWriter)){throw 'TEST_NATIVE_OUTPUT_WRITER_CHANGED'}
        }else{
            $previous=[Console]::Out
            $writer=[IO.StreamWriter]::new([Console]::OpenStandardOutput(),[Text.UTF8Encoding]::new($false,$true),4096,$true)
            $writer.NewLine=$previous.NewLine
            $writer.AutoFlush=$true
            [Console]::SetOut($writer)
            $script:NativeOutputWriter=[Console]::Out
        }
    }
    if([Console]::IsErrorRedirected){
        if($null-ne$script:NativeErrorWriter){
            if(-not[object]::ReferenceEquals([Console]::Error,$script:NativeErrorWriter)){throw 'TEST_NATIVE_ERROR_WRITER_CHANGED'}
        }else{
            $previous=[Console]::Error
            $writer=[IO.StreamWriter]::new([Console]::OpenStandardError(),[Text.UTF8Encoding]::new($false,$true),4096,$true)
            $writer.NewLine=$previous.NewLine
            $writer.AutoFlush=$true
            [Console]::SetError($writer)
            $script:NativeErrorWriter=[Console]::Error
        }
    }
}
Export-ModuleMember -Function Initialize-AiwTestNativeOutput
