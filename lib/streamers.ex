defmodule Streamers do
  defrecord M3U8, program_id: nil, path: nil, bandwidth: nil, ts_files: []

  @doc """
  Find streaming index file in the given dir
  """
  def find_index(directory) do
    files = Path.join(directory, "*.m3u8")
    if file = Enum.find(Path.wildcard(files), is_index?(&1)) do
      file
    end
  end

  defp is_index?(file) do
    File.open! file, fn(pid) ->
      IO.read(pid, 25) == "#EXTM3U\n#EXT-X-STREAM-INF"
    end
  end

  @doc """
  Extract M3U8 records from the index file
  """
  def extract_m3u8(index_file) do
    File.open! index_file, fn(pid) ->
      # Discards #EXTM3U
      IO.readline(pid)
      do_extract_m3u8(pid, Path.dirname(index_file), [])
    end
  end

  defp do_extract_m3u8(pid, dir, acc) do
    case IO.readline(pid) do
      :eof -> Enum.reverse(acc)
      stream_inf ->
        path = IO.readline(pid)
        do_extract_m3u8(pid, dir, stream_inf, path, acc)
    end
  end

  defp do_extract_m3u8(pid, dir, stream_inf, path, acc) do
    # #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=110000
    << "#EXT-X-STREAM-INF:PROGRAM-ID=", program_id, ",BANDWIDTH=", bandwidth :: binary >> = stream_inf
    path = Path.join(dir, String.strip(path))
    record = M3U8[program_id: program_id - ?0, path: path, bandwidth: binary_to_integer(String.strip(bandwidth))]
    do_extract_m3u8(pid, dir, [record|acc])
  end
  
  @doc """
  Process M3U8 records to get ts_files
  """
  def process_m3u8(m3u8s) do
    Enum.map m3u8s, do_process_m3u8(&1)
  end

  defp do_process_m3u8(M3U8[path: path] = m3u8) do
    File.open! path, fn(pid) ->
      # Discards #EXTM3U8
      IO.readline(pid)
      # Discards #EXT-X-TARGETDURATION:15
      IO.readline(pid)
      m3u8.ts_files(do_process_m3u8(pid, []))
    end
  end
  
  defp do_process_m3u8(pid, acc) do
    case IO.readline(pid) do
      "#EXT-X-ENDLIST\n" -> Enum.reverse(acc)
      # Discards #EXTINF
      extinf when is_binary(extinf) ->
        # 8bda35243c7c0a7fc69ebe1383c6464c-00001.ts
        file = IO.readline(pid) |> String.strip
        do_process_m3u8(pid, [file|acc])
    end
  end
end
