using ArgParse
function parse_cmd()
    cfg = ArgParseSettings()
    @add_arg_table cfg begin
        "--pdf", "-p"
        help = "generate figure in PDF format"
        action = :store_true
        "--folder", "-f"
        help = "name of folder containing target files"
        arg_type = String
        default = "nvme/gpu0"
    end
    return parse_args(cfg)
end

using DataFrames
using CSV
function read_csv(file::String)
    csv = CSV.read(file, DataFrame)
    return csv
end

function get_results(file::String)
    # read observed monitor
    result = read_csv(file)
    num = result."N"
    latency_write = result."latency (write) [s]"
    latency_read = result."latency (read) [s]"
    bandwidth_write = result."bandwidth (write) [byte/s]"
    bandwidth_read = result."bandwidth (read) [byte/s]"

    return num, latency_write, latency_read, bandwidth_write, bandwidth_read
end


using PyPlot
include("../util/pyplot.jl")


function main()
    # read options
    argv = parse_cmd()
    folder = argv["folder"]
    output_pdf = argv["pdf"]

    # TODO: separate の方はファイルを消してしまう．このスクリプトの方に，個別プロットも出力できるように拡張する

    # initialize matplotlib
    util_pyplot.config()
    fig_bw = util_pyplot.set_Panel(nx=1, ny=2)
    fig_lt = util_pyplot.set_Panel(nx=1, ny=2)

    for mode_id in 1:2
        if mode_id == 1
            mode = "native"
            mode_label = "w/ GDS"
        elseif mode_id == 2
            mode = "compat"
            mode_label = "w/o GDS"
        end

        for pattern_id in 1:2
            if pattern_id == 1
                pattern = "asis"
                pattern_label = ", asis"
            elseif pattern_id == 2
                pattern = "hyperslab"
                pattern_label = ", hyperslab"
            end

            # read the measured results
            num, latency_write, latency_read, bandwidth_write, bandwidth_read = get_results(string(folder, "/", pattern, "/", mode, "/log/h5gds_benchmark.csv"))

            color_tag = (2 - mode_id)
            line_tag = (pattern_id - 1)
            pt_tag = (2 - mode_id) + 2 * (pattern_id - 1)

            fig_bw.ax[begin, 2].plot(num, bandwidth_write, util_pyplot.call(fig_bw.point, id=pt_tag), markersize=fig_bw.ms, linestyle=util_pyplot.call(fig_bw.line, id=line_tag), linewidth=fig_bw.lw, color=util_pyplot.call(fig_bw.color, id=color_tag), label=string(mode_label, pattern_label))
            fig_bw.ax[begin, 1].plot(num, bandwidth_read, util_pyplot.call(fig_bw.point, id=pt_tag), markersize=fig_bw.ms, linestyle=util_pyplot.call(fig_bw.line, id=line_tag), linewidth=fig_bw.lw, color=util_pyplot.call(fig_bw.color, id=color_tag), label=string(mode_label, pattern_label))

            fig_lt.ax[begin, 2].plot(num, latency_write, util_pyplot.call(fig_lt.point, id=pt_tag), markersize=fig_lt.ms, linestyle=util_pyplot.call(fig_lt.line, id=line_tag), linewidth=fig_lt.lw, color=util_pyplot.call(fig_lt.color, id=color_tag), label=string(mode_label, pattern_label))
            fig_lt.ax[begin, 1].plot(num, latency_read, util_pyplot.call(fig_lt.point, id=pt_tag), markersize=fig_lt.ms, linestyle=util_pyplot.call(fig_lt.line, id=line_tag), linewidth=fig_lt.lw, color=util_pyplot.call(fig_lt.color, id=color_tag), label=string(mode_label, pattern_label))
        end
    end

    fig_bw.ax[begin, 2].set_ylabel(L"Bandwidth~$\bqty{\unit{B.s^{-1}}}$", fontsize=fig_bw.fs)
    fig_bw.ax[begin, 1].set_ylabel(L"Bandwidth~$\bqty{\unit{B.s^{-1}}}$", fontsize=fig_bw.fs)
    fig_bw.ax[begin, begin].set_xlabel(L"$N$", fontsize=fig_bw.fs)
    fig_lt.ax[begin, 2].set_ylabel(L"Latency~$\bqty{\unit{s}}$", fontsize=fig_lt.fs)
    fig_lt.ax[begin, 1].set_ylabel(L"Latency~$\bqty{\unit{s}}$", fontsize=fig_lt.fs)
    fig_lt.ax[begin, begin].set_xlabel(L"$N$", fontsize=fig_lt.fs)

    for at in fig_bw.ax
        at.loglog()
        at.grid()
    end
    for at in fig_lt.ax
        at.loglog()
        at.grid()
    end

    # add caption
    for ii in 1:fig_bw.nx
        for jj in 1:fig_bw.ny
            maptag::String = ""
            if jj == 1
                maptag = "read"
            elseif jj == 2
                maptag = "write"
            end
            caption = string("(", Char(97 + (ii - 1) + fig_bw.nx * (fig_bw.ny - jj)), ")")
            at = fig_bw.ax[ii, jj]
            at.text(0.05, 0.95, string(caption, "~", maptag), color="black", fontsize=fig_bw.fs, horizontalalignment="left", verticalalignment="top", transform=at.transAxes, bbox=Dict("facecolor" => "white", "edgecolor" => "None", "alpha" => 0.75))
        end
    end
    for ii in 1:fig_lt.nx
        for jj in 1:fig_lt.ny
            maptag::String = ""
            if jj == 1
                maptag = "read"
            elseif jj == 2
                maptag = "write"
            end
            caption = string("(", Char(97 + (ii - 1) + fig_lt.nx * (fig_lt.ny - jj)), ")")
            at = fig_lt.ax[ii, jj]
            at.text(0.05, 0.95, string(caption, "~", maptag), color="black", fontsize=fig_lt.fs, horizontalalignment="left", verticalalignment="top", transform=at.transAxes, bbox=Dict("facecolor" => "white", "edgecolor" => "None", "alpha" => 0.75))
        end
    end

    # add legends
    handles, labels = fig_bw.ax[begin, 2].get_legend_handles_labels()
    fig_bw.ax[begin, 2].legend(handles, labels, numpoints=1, handlelength=2.0, loc="best", fontsize=fig_bw.fs)
    handles, labels = fig_lt.ax[begin, 2].get_legend_handles_labels()
    fig_lt.ax[begin, 2].legend(handles, labels, numpoints=1, handlelength=2.0, loc="best", fontsize=fig_lt.fs)

    # save figures
    if !ispath("fig")
        mkdir("fig")
    end
    fig_bw.fig.savefig(string("fig/bandwidth", ".png"), format="png", dpi=100, bbox_inches="tight")
    fig_lt.fig.savefig(string("fig/latency", ".png"), format="png", dpi=100, bbox_inches="tight")
    if output_pdf
        fig_bw.fig.savefig(string("fig/bandwidth", ".pdf"), format="pdf", bbox_inches="tight")
        fig_lt.fig.savefig(string("fig/latency", ".pdf"), format="pdf", bbox_inches="tight")
    end

    fig_bw = nothing
    fig_lt = nothing
    PyPlot.close("all")

    return nothing

end


main()
