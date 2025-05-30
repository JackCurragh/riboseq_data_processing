

process STAR_ALIGN {
    tag "$meta.id"
    label 'high'

    conda "bioconda::star=2.7.10a"

    // Add publishing directives
    publishDir path: "${params.outdir}/star_align", mode: 'link', saveAs: { 
        filename -> if (filename.endsWith('toTranscriptome.out.bam')) return "transcriptome_bam/$filename" 
        else if  (filename.endsWith('.bam')) return "bam/$filename"
        else if (filename.endsWith('.out')) return "logs/$filename" else null 
        }


    input:
    tuple val(meta), path(reads)
    path index
    path gtf

    output:
    tuple val(meta), path("*.Aligned.sortedByCoord.out.bam"), emit: bam
    tuple val(meta), path("*.Aligned.toTranscriptome.out.bam"), emit: transcriptome_bam, optional: true
    tuple val(meta), path("*.Log.final.out"), emit: log
    path "versions.yml", emit: versions

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def trim_front = params.trim_front > 0 ? "--clip3pNbases ${params.trim_front}" : ''
    def alignment_type = params.alignment_type == 'Local' ? '--alignEndsType Local' : ''
    def allow_introns = params.allow_introns ? '--alignIntronMax 1000000 --alignMatesGapMax 1000000' : ''
    def unzip_command = reads.name.endsWith('.gz') ? 'zcat' : 'cat'
    def output_transcriptome_bam = params.save_star_transcriptome_bam ? "--quantMode TranscriptomeSAM" : ""

    """
    STAR \
        --genomeDir $index \
        --readFilesIn $reads \
        --runThreadN ${task.cpus} \
        --outSAMtype BAM SortedByCoordinate \
        --outSAMattributes NH HI AS nM \
        --outFilterMultimapNmax 10 \
        --outFilterMismatchNmax ${params.mismatches} \
        --readFilesCommand $unzip_command \
        $output_transcriptome_bam \
        $alignment_type \
        $allow_introns \
        $trim_front \
        $args \
        --outFileNamePrefix ${prefix}. \
        --sjdbGTFfile $gtf \


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        star: \$(STAR --version | sed -e "s/STAR_//g")
    END_VERSIONS
    """
}

